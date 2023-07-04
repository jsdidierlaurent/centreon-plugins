#
# Copyright 2023 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package apps::mq::rabbitmq::restapi::mode::nodeusage;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold catalog_status_calc);

sub custom_status_output {
    my ($self, %options) = @_;

    return sprintf(
        'status: %s, watermark: %s',
        $self->{result_values}->{status},
        $self->{result_values}->{watermark}
    );
 
   my $msg = "status: '" . $self->{result_values}->{status} . "'";
    return $msg;
}

sub custom_ram_usage_output {
    my ($self, %options) = @_;

    return sprintf(
        'Memory total: %s %s used: %s %s (%.2f%%) free: %s %s (%.2f%%)',
        $self->{perfdata}->change_bytes(value => $self->{result_values}->{mem_limit}),
        $self->{perfdata}->change_bytes(value => $self->{result_values}->{mem_used}),
        $self->{result_values}->{mem_used_prct},
        $self->{perfdata}->change_bytes(value => $self->{result_values}->{mem_free}),
        $self->{result_values}->{mem_free_prct}
    );
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'node', type => 1, cb_prefix_output => 'prefix_node_output', message_multiple => 'All nodes are ok', skipped_code => { -10 => 1 } },
    ];

    $self->{maps_counters}->{node} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'status' }, { name => 'watermark' }, { name => 'display' } ],
                closure_custom_calc => \&catalog_status_calc,
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold,
            }
        },
        { label => 'read', nlabel => 'node.io.read.usage.bytespersecond', set => {
                key_values => [ { name => 'io_read_bytes', per_second => 1 }, { name => 'display' } ],
                output_template => 'read i/o : %s %s/s',
                output_change_bytes => 1,
                perfdatas => [
                    { template => '%d', unit => 'B/s', min => 0, label_extra_instance => 1, instance_use => 'display' }
                ]
            }
        },
        { label => 'write', nlabel => 'node.io.write.usage.bytespersecond', set => {
                key_values => [ { name => 'io_write_bytes', per_second => 1 }, { name => 'display' } ],
                output_template => 'write i/o : %s %s/s',
                output_change_bytes => 1,
                perfdatas => [
                    { template => '%d', unit => 'B/s', min => 0, label_extra_instance => 1, instance_use => 'display' }
                ]
            }
        },
        { label => 'memory-usage', nlabel => 'node.memory.usage.bytes', set => {
                key_values => [ { name => 'mem_used' }, { name => 'mem_free' }, { name => 'mem_used_prct' }, { name => 'mem_free_prct' }, { name => 'mem_limit' } ],
                closure_custom_output => $self->can('custom_ram_usage_output'),
                perfdatas => [
                    { template => '%d', min => 0, max => 'total', unit => 'B', cast_int => 1 }
                ]
            }
        },
        { label => 'memory-usage-free', display_ok => 0, nlabel => 'node.memory.free.bytes', set => {
                key_values => [ { name => 'mem_free' }, { name => 'mem_used' }, { name => 'mem_used_prct' }, { name => 'mem_free_prct' }, { name => 'mem_limit' } ],
                closure_custom_output => $self->can('custom_ram_usage_output'),
                perfdatas => [
                    { template => '%d', min => 0, max => 'total', unit => 'B', cast_int => 1 }
                ]
            }
	},
	{ label => 'memory-usage-prct', display_ok => 0, nlabel => 'node.memory.usage.percentage', set => {
                key_values => [ { name => 'mem_used_prct' }, { name => 'mem_free' }, { name => 'mem_used' }, { name => 'mem_free_prct' }, { name => 'mem_limit' } ],
                closure_custom_output => $self->can('custom_ram_usage_output'),
                perfdatas => [
                    { template => '%.2f', min => 0, max => 100, unit => '%' }
                ]
            }
	}

    ];
}

sub prefix_node_output {
    my ($self, %options) = @_;

    return "Node '" . $options{instance_value}->{display} . "' ";
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, statefile => 1, force_new_perfdata => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => {
        'filter-name:s'     => { name => 'filter_name' },
        'warning-status:s'  => { name => 'warning_status', default => '' },
        'critical-status:s' => { name => 'critical_status', default => '%{status} ne "running" || %{watermark} ne "notrunning"' },
    });
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $self->change_macros(macros => ['warning_status', 'critical_status']);
}

sub manage_selection {
    my ($self, %options) = @_;

    my $result = $options{custom}->query(url_path => '/api/nodes/?columns=name,running,io_write_bytes,io_read_bytes,mem_used,mem_limit,mem_alarm');

    $self->{node} = {};
    foreach (@$result) {
        next if (defined($self->{option_results}->{filter_name}) && $self->{option_results}->{filter_name} ne '' 
            && $_->{name} !~ /$self->{option_results}->{filter_name}/);

        $self->{node}->{$_->{name}} = {
            display => $_->{name},
            io_write_bytes => $_->{io_write_bytes},
            io_read_bytes => $_->{io_read_bytes},
            mem_used => $_->{mem_used},
            mem_limit => $_->{mem_limit},
            mem_free => $_->{mem_limit} - $_->{mem_used},
            mem_used_prct => 100 - (($_->{mem_limit} - $_->{mem_used}) * 100 / $_->{mem_limit}),
            mem_free_prct => ($_->{mem_limit} - $_->{mem_used}) * 100 / $_->{mem_limit},
            watermark => $_->{mem_alarm} ? 'running' : 'notrunning',
            status => $_->{running} ? 'running' : 'notrunning',
        };
    }

    if (scalar(keys %{$self->{node}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => 'No node found');
        $self->{output}->option_exit();
    }

    $self->{cache_name} = "rabbitmq_" . $self->{mode} . '_' . $options{custom}->get_hostname() . '_' . $options{custom}->get_port() . '_' .
        (defined($self->{option_results}->{filter_name}) ? md5_hex($self->{option_results}->{filter_name}) : md5_hex('all')) . '_' .
        (defined($self->{option_results}->{filter_counters}) ? md5_hex($self->{option_results}->{filter_counters}) : md5_hex('all'));
}

1;

__END__

=head1 MODE

Check node usage.

=over 8

=item B<--filter-name>

Filter node name (Can use regexp).

=item B<--warning-status>

Set warning threshold for status (Default: '').
Can used special variables like: %{status}, %{watermark}, %{display}

=item B<--critical-status>

Set critical threshold for status (Default: '%{status} ne "running" || %{watermark} ne "notrunning"').
Can used special variables like: %{status}, %{watermark}, %{display}

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'read', 'write', 'memory-usage', 'memory-free', 'memory-usage-prct'.

=back

=cut
