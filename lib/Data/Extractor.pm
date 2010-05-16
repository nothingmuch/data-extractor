package Data::Extractor;
use Moose;

#use Moose::Autobox; # used lexically below
use Try::Tiny;
use JSON;
use Carp;

use namespace::autoclean;

has unknown_method_is_fatal => (
    isa => "Bool",
    is  => "ro",
    default => 1,
);

has "compile_method" => (
    isa => "Str|CodeRef",
    is  => "ro",
    default => "default_compile_method",
);

has cache => (
    isa => "Bool",
    is  => "ro",
    default => 1,
);

has _cache => (
    isa => "HashRef",
    is  => "ro",
    default => sub { return { } },
);


sub extract {
    my ( $self, $data, @paths ) = @_;

    $self->traverse($data, map { $self->parse_path($_) } @paths );
}

sub traverse {
    my ( $self, $data, @ops ) = @_;

    return $data unless @ops;

    my ( $next, @tail ) = @ops;

    if ( not ref $next ) {
        # simple subscript, ["foo"]
        if ( ref $data eq 'ARRAY' ) {
            return $self->traverse( $data->[$next], @tail );
        } elsif ( ref $data eq 'HASH' ) {
            return $self->traverse( $data->{$next}, @tail );
        } else {
            croak "Simple subscripts only apply to hashes and arrays";
        }
    } else {
        if ( ref $next eq 'ARRAY' ) {
            return $self->traverse([ map { scalar $self->traverse($data, $_) } @$next ], @tail);
        } elsif ( ref $next eq 'CODE' ) {
            return $self->traverse( scalar($data->$next($self)), @tail );
        } elsif ( ref $next eq 'SCALAR' ) {
            # DWIM mode:
            # foo.bar, 'bar' is either a key or a method (autoboxed or otherwise)
            if ( ref($data) eq 'HASH' ) {
                # keys on hashes never fail, even when fatal

                if ( exists $data->{$$next} ) {
                    return $self->traverse( $data->{$$next}, @tail );
                } else {
                    return $self->traverse(
                        $data,
                        $self->_compile_nonfatal_method(
                            method => $$next,
                            catch => sub {
                                return $_[0]{$$next};
                            },
                        ),
                        @tail,
                    );
                }
            } else {
                # handles objects, classes and autoboxed method calls on anything
                return $self->traverse($data, $self->_compile_method_wrapper( method => $$next ), @tail);
            }
        }
    }

    croak "Not sure what kind of operation $next is";
}

use Moose::Autobox;

sub _compile_method {
    my ( $self, %args ) = @_;

    my $hook = $self->compile_method;

    my $method = $args{method};
    my @args = @{ $args{args} || [] };

    $self->$hook($method, @args);
}

sub default_compile_method {
    my ( $self, $method, @args ) = @_;

    return sub {
        $_[0]->$method(@args);
    };
}

sub _compile_nonfatal_method {
    my ( $self, %args ) = @_;

    my $catch  = $args{catch};
    my $method = $args{method};

    my $body = $self->_compile_method(%args);

    return sub {
        my $inv = shift;

        try {
            return $inv->$body;
        } catch {
            die $_ if ref($_);
            die $_ unless /^(?:Can't locate object method "\Q$method\E" via package|Can't call method "\Q$method\E" on)/;

            if ( $catch ) {
                return $inv->$catch;
            } else {
                return;
            }
        };
    }
}

sub _compile_method_wrapper {
    my ( $self, @args ) = @_;

    if ( $self->unknown_method_is_fatal ) {
        return $self->_compile_method(@args);
    } else {
        return $self->_compile_nonfatal_method(@args);
    }
}

# FIXME can't have expressions in params/subscripts yet, because you can't
# extend this with new word types
# gotta write a subclassible parser =(
my $json = JSON->new->allow_nonref->relaxed;

my $delim = qr/\./;
my $ident = qr/[A-Za-z_]\w*/;
my $open_params = qr{\(};
my $close_params = qr{\)};
my $open_subscript = qr{\[};
my $close_subscript = qr{\]};

sub parse_path {
    my ( $self, $path ) = @_;

    return $path if ref $path;

    if ( $self->cache ) {
        if ( my $res = $self->_cache->{$path} ) {
            return @$res;
        } else {
            return @{ $self->_cache->{$path} = [ $self->_parse_path($path) ] };
        }
    } else {
        return $self->_parse_path($path);
    }
}

sub _parse_path {
    my ( $self, $path ) = @_;

    my @ret;

    parse: {
        my $p = pos($path);

        # parse a subscript action, either an ident or an open bracket
        if ( $path =~ /\G($ident)/g ) {
            my $name = $1;

            $p = pos($path);

            # followed by a subscript or arguments
            if ( $path =~ /\G$open_params/g ) {
                $p = pos($path);

                my @args;

                unless ( $path =~ /\G$close_params/g ) {
                    pos($path) = $p;
                    @args = $self->_parse_params($path);
                    unless ( $path =~ /\G$close_params/g ) {
                        croak "expected ')'";
                    }
                }

                push @ret, $self->_compile_method_wrapper( method => $name, args => \@args );
            } else {
                push @ret, \$name;
                pos($path) = $p;
            }
        } else {
            pos($path) = $p;

            if ( $path =~ /\G(?=$open_subscript)/g ) {
                my @subscript = $self->_parse_subscript($path);

                if ( @subscript == 1 ) {
                    push @ret, $subscript[0]; # simple subscript
                } else {
                    push @ret, \@subscript;
                }
            } else {
                croak "unexpected data while parsing path, expected identifier or subscript";
            }
        }

        if ( pos($path) == length($path) ) {
            pos($path) = undef;
            last parse;
        } elsif ( $path =~ /\G(?:(?=$open_subscript)|$delim)/g ) {
                redo parse;
        } else {
            croak "unexpected data while parsing path, expected EOF or path delimiter";
        }
    };

    return @ret;
}

sub _parse_subscript {
    my ( $self, $path ) = @_;

    my $data = substr($path, pos($_[1]));
    my $len = length($data);

    $json->incr_reset;

    my $ret = $json->incr_parse($data);

    if ( ref($ret) eq 'ARRAY') {
        pos($_[1]) = pos($_[1]) + ( length($data) - length($json->incr_text) );
        $json->incr_reset;
        return @$ret;
    } else {
        $json->incr_reset;
        croak "Error parsing JSON, expected array but found $data";
    }
}

sub _parse_params {
    my ( $self, $path ) = @_;

    my $data = substr($path, pos($_[1]));
    my $len = length($data);

    $json->incr_reset;
    $json->incr_parse($data);

    my @out;

    parse_json: {
        if ( my $data = $json->incr_parse ) {
            push @out, $data;

            if ( $json->incr_text =~ s/^ \s* , //x ) {
                redo parse_json;
            }
        } else {
            croak "error from json";
        }
    }

    pos($_[1]) = pos($_[1]) + ( length($data) - length($json->incr_text) );

    $json->incr_reset;

    return @out;
}

__PACKAGE__->meta->make_immutable;

# ex: set sw=4 et:

__PACKAGE__

__END__
