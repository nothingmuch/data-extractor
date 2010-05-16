package Data::Extractor;
use Moose;

use JSON;
use Carp;

use namespace::autoclean;

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
    my ( $self, $data, $path ) = @_;

    $self->traverse($data, $self->parse_path($path) );
}

sub traverse {
    my ( $self, $data, $next, @tail ) = @_;

    use Devel::PartialDump qw(warn);

    return $data unless defined $next;

    if ( ref $next eq 'ARRAY' ) {
        return $self->traverse([ map { $self->traverse($data, $_) } @$next ], @tail);
    } elsif ( ref $next eq 'CODE' ) {
        $self->traverse( $data->$next($self), @tail );
    } elsif ( blessed($data) ) {
        if ( $data->can($next) ) {
            $self->traverse( $data->$next, @tail );
        } else {
            return;
        }
    } elsif ( ref($data) eq 'HASH' ) {
        if ( exists $data->{$next} ) {
            return $self->traverse( $data->{$next}, @tail );
        } else {
            return $self->traverse($data, $self->_compile_method($next), @tail);
        }
    } elsif ( ref($data) eq 'ARRAY' ) {
        if ( Scalar::Util::looks_like_number($next) ) {
            return $self->traverse( $data->[$next], @tail );
        } else {
            return $self->traverse($data, $self->_compile_method($next), @tail);
        }
    } else {
        $self->traverse($data, $self->_compile_method($next), @tail);
    }
}

sub _compile_method {
    my ( $self, $method, @args ) = @_;
    sub {
        use Moose::Autobox;
        my $inv = shift;
        $inv->$method(@args);
    };
}

my $json = JSON->new->allow_nonref;
my $delim = qr/\./;
my $ident = qr/[A-Za-z_]\w*/;
my $open_params = qr{\(};
my $close_params = qr{\)};
my $open_subscript = qr{\[};
my $close_subscript = qr{\]};

sub parse_path {
    my ( $self, $path ) = @_;

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
            push @ret, $1;

            $p = pos($path);

            # followed by a subscript or arguments
            if ( $path =~ /\G$open_params/g ) {
                $p = pos($path);

                my $method = pop @ret;

                my @args;

                unless ( $path =~ /\G$close_params/g ) {
                    pos($path) = $p;
                    @args = $self->_parse_params($path);
                    unless ( $path =~ /\G$close_params/g ) {
                        croak "expected ')'";
                    }
                }

                push @ret, $self->_compile_method($method, @args);
            } else {
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
