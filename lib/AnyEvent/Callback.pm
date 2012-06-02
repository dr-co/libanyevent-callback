package AnyEvent::Callback;

use 5.014002;
use strict;
use warnings;

require Exporter;
use base 'Exporter';
use Carp;

our @EXPORT = qw(CB);

our $VERSION = '0.01';


=head1 NAME

=head1 SYNOPSIS

    use AnyEvent::Something;


    # usually watchers are looked as:
    AE::something @args, sub { ... };
    AE::something
        @args,
        sub { ... },    # result
        sub { ... };    # error


    use AnyEvent::Callback;

    AE::something @args, CB { ... };
    AE::something @args,
        CB sub { ... },     # result
            sub { ... };    # error

Inside Your callback You can:

    sub my_watcher {
        my $cb = pop;
        my @args = @_;

        # ...

        $cb->error( @error );   # error callback will be called
        # or:
        $cb->( $value );        # result callback will be called
    }

Also You can create callback's queue:

    sub my_watcher {
        my $cb = pop;

        # ...

        AE::something @args, $cb->CB( sub { ... } );
        # or:
        AE::something @args, $cb->CB( sub { ... } );
        AE::something @args, $cb->CB( sub { ... }, sub { ... } );
    }


=head1 DESCRIPTION

The module allows You to create callback's hierarchy. Also the module groups
error and result callbacks into one object.

Also the module checks if one callback was called by watcher or not.
If a watcher doesn't call result or error callback, error callback will be
called automatically.

Also the module checks if a callback was called reentrant. In the case the
module will complain (using L<Croak/carp>).

If a watcher touches error callback and if superior didn't define error
callback, the module will call error callback upwards of hierarchy. Example:

    AE::something @args, CB \&my_watcher, \&on_error;

    sub on_error {

    }

    sub my_watcher {
        my $cb = pop;

        ...

        the_other_watcher $cb->CB( sub {    # error callback wasn't defined
            my $cb = pop;
            ...
            yet_another_watcher1 $cb->CB( sub {
                my $cb = pop;
                ...
                $cb->( 123 );   # upwards callback

            });
            yet_another_watcher2 $cb->CB( sub {
                my $cb = pop;
                ...

                $cb->error( 456 );  # on_error will be called

            });


        });
    }

=cut

use overload
    '&{}' => sub {
        my ($self) = shift;
        sub {
            $self->{called}++;
            carp "Repeated callback calling: $self->{called}"
                if $self->{called} > 1;
            carp "Calling result callback after error callback"
                if $self->{ecalled};
            $self->{cb}->(@_) if $self->{cb};
            delete $self->{cb};
            delete $self->{ecb};
            delete $self->{parent};
            return;
        };
    },
    bool => sub { 1 } # for 'if ($cb)'
;


sub CB(&;&) {

    my $parent;
    my ($cb, $ecb) = @_;

    ($parent, $cb, $ecb) = @_ unless 'CODE' eq ref $cb;

    croak 'Callback must be CODEREF' unless 'CODE' eq ref $cb;
    croak 'Error callback must be CODEREF or undef'
        unless 'CODE' eq ref $ecb or !defined $ecb;

    my $self = bless {
        cb      => $cb,
        ecb     => $ecb,
        parent  => $parent,
        called  => 0,
        ecalled => 0,
    } => __PACKAGE__;

    $self;
}

sub error {
    my ($self, @error) = @_;

    $self->{ecalled}++;
    carp "Repeated error callback calling: $self->{ecalled}"
        if $self->{ecalled} > 1;
    carp "Calling error callback after result callback"
        if $self->{called};

    if ($self->{ecb}) {
        $self->{ecb}( @error );
        delete $self->{ecb};
        delete $self->{cb};
        delete $self->{parent};
        return;
    }

    delete $self->{ecb};
    delete $self->{cb};
    my $parent = delete $self->{parent};

    unless($parent) {
        carp "Uncaught error: @error";
        return;
    }

    $parent->error( @error );
    return;
}

sub DESTROY {
    my ($self) = @_;
    return if $self->{called} or $self->{ecalled};
    $self->error("no one touched registered callback");
    delete $self->{cb};
    delete $self->{ecb};
}

1;
