#line 1
# $Id: MockModule.pm,v 1.7 2005/03/24 22:23:38 simonflack Exp $
package Test::MockModule;
use strict qw/subs vars/;
use vars qw/$VERSION/;
use Scalar::Util qw/reftype weaken/;
use Carp;
$VERSION = '0.05';#sprintf'%d.%02d', q$Revision: 1.7 $ =~ /: (\d+)\.(\d+)/;

my %mocked;
sub new {
    my $class = shift;
    my ($package, %args) = @_;
    if ($package && (my $existing = $mocked{$package})) {
        return $existing;
    }

    croak "Cannot mock $package" if $package && $package eq $class;
    unless (_valid_package($package)) {
        $package = 'undef' unless defined $package;
        croak "Invalid package name $package";
    }

    unless ($args{no_auto} || ${"$package\::VERSION"}) {
        (my $load_package = "$package.pm") =~ s{::}{/}g;
        TRACE("$package is empty, loading $load_package");
        require $load_package;
    }

    TRACE("Creating MockModule object for $package");
    my $self = bless {
        _package => $package,
        _mocked  => {},
    }, $class;
    $mocked{$package} = $self;
    weaken $mocked{$package};
    return $self;
}

sub DESTROY {
    my $self = shift;
    $self->unmock_all;
}

sub get_package {
    my $self = shift;
    return $self->{_package};
}

sub mock {
    my $self = shift;

    while (my ($name, $value) = splice @_, 0, 2) {
        my $code = sub { };
        if (ref $value && reftype $value eq 'CODE') {
            $code = $value;
        } elsif (defined $value) {
            $code = sub {$value};
        }

        TRACE("$name: $code");
        croak "Invalid subroutine name: $name" unless _valid_subname($name);
        my $sub_name = _full_name($self, $name);
        if (!$self->{_mocked}{$name}) {
            TRACE("Storing existing $sub_name");
            $self->{_mocked}{$name} = 1;
            $self->{_orig}{$name}   = defined &{$sub_name} ? \&$sub_name
                : $self->{_package}->can($name);
        }
        TRACE("Installing mocked $sub_name");
        _replace_sub($sub_name, $code);
    }
}

sub original {
    my $self = shift;
    my ($name) = @_;
    return carp _full_name($self, $name) . " is not mocked"
            unless $self->{_mocked}{$name};
    return $self->{_orig}{$name};
}

sub unmock {
    my $self = shift;

    for my $name (@_) {
        croak "Invalid subroutine name: $name" unless _valid_subname($name);

        my $sub_name = _full_name($self, $name);
        unless ($self->{_mocked}{$name}) {
            carp $sub_name . " was not mocked";
            next;
        }

        TRACE("Restoring original $sub_name");
        _replace_sub($sub_name, $self->{_orig}{$name});
        delete $self->{_mocked}{$name};
        delete $self->{_orig}{$name};
    }
    return $self;
}

sub unmock_all {
    my $self = shift;
    foreach (keys %{$self->{_mocked}}) {
        $self->unmock($_);
    }
}

sub is_mocked {
    my $self = shift;
    my ($name) = shift;
    return $self->{_mocked}{$name};
}

sub _full_name {
    my ($self, $sub_name) = @_;
    sprintf "%s::%s", $self->{_package}, $sub_name;
}

sub _valid_package {
    defined($_[0]) && $_[0] =~ /^[a-z_]\w*(?:::\w+)*$/i;
}

sub _valid_subname {
    $_[0] =~ /^[a-z_]\w*$/i;
}

sub _replace_sub {
    my ($sub_name, $coderef) = @_;
    # from Test::MockObject
    local $SIG{__WARN__} = sub { warn $_[0] unless $_[0] =~ /redefined/ };
    if (defined $coderef) {
        *{$sub_name} = $coderef;
    } else {
        TRACE("removing subroutine: $sub_name");
        my ($package, $sub) = $sub_name =~ /(.*::)(.*)/;
        my %symbols = %{$package};

        # save a copy of all non-code slots
        my %slot;
        foreach (qw(ARRAY FORMAT HASH IO SCALAR)) {
            next unless defined(my $elem = *{$symbols{$sub}}{$_});
            $slot{$_} = $elem;
        }

        # clear the symbol table entry for the subroutine
        undef *$sub_name;

        # restore everything except the code slot
        return unless keys %slot;
        foreach (keys %slot) {
            *$sub_name = $slot{$_};
        }
    }
}

# Log::Trace stubs
sub TRACE {}
sub DUMP  {}

1;

#line 278
