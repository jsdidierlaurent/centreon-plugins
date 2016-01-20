#
# Copyright 2016 Centreon (http://www.centreon.com/)
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

package network::f5::bigip::mode::poolstatus;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

my $thresholds = {
    pool => [
        ['none', 'CRITICAL'],
        ['green', 'OK'],
        ['yellow', 'WARNING'],
        ['red', 'CRITICAL'],
        ['blue', 'UNKNOWN'],
        ['gray', 'UNKNOWN'],
    ],
};
my $instance_mode;

sub custom_threshold_output {
    my ($self, %options) = @_;
    
    return $instance_mode->get_severity(section => 'pool', value => $self->{result_values}->{AvailState});
}

sub custom_status_calc {
    my ($self, %options) = @_;
    
    $self->{result_values}->{AvailState} = $options{new_datas}->{$self->{instance} . '_AvailState'};
    return 0;
}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'pool', type => 1, cb_prefix_output => 'prefix_pool_output', message_multiple => 'All Pools are ok' },
    ];
    $self->{maps_counters}->{pool} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'AvailState' } ],
                closure_custom_calc => $self->can('custom_status_calc'),
                output_template => 'Status : %s', output_error_template => 'Status : %s',
                output_use => 'AvailState',
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => $self->can('custom_threshold_output'),
            }
        },
    ];
}

sub prefix_pool_output {
    my ($self, %options) = @_;
    
    return "Pool '" . $options{instance_value}->{Name} . "' ";
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "filter-name:s"           => { name => 'filter_name' },
                                  "threshold-overload:s@"   => { name => 'threshold_overload' },
                                });
    
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
    
    $instance_mode = $self;
    
    $self->{overload_th} = {};
    foreach my $val (@{$self->{option_results}->{threshold_overload}}) {
        if ($val !~ /^(.*?),(.*?),(.*)$/) {
            $self->{output}->add_option_msg(short_msg => "Wrong threshold-overload option '" . $val . "'.");
            $self->{output}->option_exit();
        }
        my ($section, $status, $filter) = ($1, $2, $3);
        if ($self->{output}->is_litteral_status(status => $status) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong threshold-overload status '" . $val . "'.");
            $self->{output}->option_exit();
        }
        $self->{overload_th}->{$section} = [] if (!defined($self->{overload_th}->{$section}));
        push @{$self->{overload_th}->{$section}}, {filter => $filter, status => $status};
    }
}

sub get_severity {
    my ($self, %options) = @_;
    my $status = 'UNKNOWN'; # default 
    
    if (defined($self->{overload_th}->{$options{section}})) {
        foreach (@{$self->{overload_th}->{$options{section}}}) {            
            if ($options{value} =~ /$_->{filter}/i) {
                $status = $_->{status};
                return $status;
            }
        }
    }
    foreach (@{$thresholds->{$options{section}}}) {           
        if ($options{value} =~ /$$_[0]/i) {
            $status = $$_[1];
            return $status;
        }
    }
    
    return $status;
}

my %map_pool_status = (
    0 => 'none',
    1 => 'green',
    2 => 'yellow',
    3 => 'red',
    4 => 'blue', # unknown
    5 => 'gray',
);
my %map_pool_enabled = (
    0 => 'none',
    1 => 'enabled',
    2 => 'disabled',
    3 => 'disabledbyparent',
);

# New OIDS
my $mapping = {
    new => {
        AvailState => { oid => '.1.3.6.1.4.1.3375.2.2.5.5.2.1.2', map => \%map_pool_status },
        EnabledState => { oid => '.1.3.6.1.4.1.3375.2.2.5.5.2.1.3', map => \%map_pool_enabled },
        StatusReason => { oid => '.1.3.6.1.4.1.3375.2.2.5.5.2.1.5' },
    },
    old => {
        AvailState => { oid => '.1.3.6.1.4.1.3375.2.2.5.1.2.1.18', map => \%map_pool_status },
        EnabledState => { oid => '.1.3.6.1.4.1.3375.2.2.5.1.2.1.19', map => \%map_pool_enabled },
        StatusReason => { oid => '.1.3.6.1.4.1.3375.2.2.5.1.2.1.21' },
    },
};
my $oid_ltmPoolStatusEntry = '.1.3.6.1.4.1.3375.2.2.5.5.2.1'; # new
my $oid_ltmPoolEntry = '.1.3.6.1.4.1.3375.2.2.5.1.2.1'; # old

sub manage_selection {
    my ($self, %options) = @_;

    $self->{results} = $options{snmp}->get_multiple_table(oids => [
                                                            { oid => $oid_ltmPoolEntry, start => $mapping->{old}->{AvailState}->{oid} },
                                                            { oid => $oid_ltmPoolStatusEntry, start => $mapping->{new}->{AvailState}->{oid} },
                                                         ],
                                                         , nothing_quit => 1);
    
    my ($branch, $map) = ($oid_ltmPoolStatusEntry, 'new');
    if (!defined($self->{results}->{$oid_ltmPoolStatusEntry}) || scalar(keys %{$self->{results}->{$oid_ltmPoolStatusEntry}}) == 0)  {
        ($branch, $map) = ($oid_ltmPoolEntry, 'old');
    }
    
    $self->{pool} = {};
    foreach my $oid (keys %{$self->{results}->{$branch}}) {
        next if ($oid !~ /^$mapping->{$map}->{AvailState}->{oid}\.(.*)$/);
        my $instance = $1;
        my $result = $options{snmp}->map_instance(mapping => $mapping->{$map}, results => $self->{results}->{$branch}, instance => $instance);
        
        $result->{Name} = '';
        foreach (split /\./, $instance) {
            $result->{Name} .= chr  if ($_ >= 32 && $_ <= 126);
        }
        if (defined($self->{option_results}->{filter_name}) && $self->{option_results}->{filter_name} ne '' &&
            $result->{Name} !~ /$self->{option_results}->{filter_name}/) {
            $self->{output}->output_add(long_msg => "Skipping  '" . $result->{Name} . "': no matching filter name.");
            next;
        }
        if ($result->{EnabledState} !~ /enabled/) {
            $self->{output}->output_add(long_msg => "Skipping  '" . $result->{Name} . "': state is '$result->{EnabledState}'.");
            next;
        }
        $result->{StatusReason} = '-' if (!defined($result->{StatusReason}) || $result->{StatusReason} eq '');
        
        $self->{pool}->{$instance} = { %$result };
    }
    
    if (scalar(keys %{$self->{pool}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No entry found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check Pools status.

=over 8

=item B<--filter-name>

Filter by name (regexp can be used).

=item B<--threshold-overload>

Set to overload default threshold values (syntax: section,status,regexp)
It used before default thresholds (order stays).
Example: --threshold-overload='pool,CRITICAL,^(?!(green)$)'

=back

=cut
