package Tangence::Compiler::Parser;

use strict;
use warnings;

use feature qw( switch ); # we like given/when

use File::Slurp qw( slurp );
use File::Basename qw( dirname );

use Tangence::Constants;

sub from_file
{
   my $class = shift;
   my ( $filename ) = @_;

   $class->from_string( scalar(slurp $filename),
      filename => $filename,
   );
}

sub from_string
{
   my $class = shift;
   my ( $str, %args ) = @_;

   my $self = bless {
      str => $str,

      line => 1,

      %args,
   }, $class;

   pos $self->{str} = 0;

   return $self->parse;
}

sub expect
{
   my $self = shift;
   my ( $expect ) = @_;

   ref $expect or $expect = qr/\Q$expect/;

   $self->skip_ws;
   $self->{str} =~ m/\G$expect/gc or
      $self->fail( "Expected $expect" );
}

sub skip_ws
{
   my $self = shift;

   $self->{str} =~ m/\G([\s\n]+)/gc;

   # Since this is the only method that can consume linefeeds, we'll account
   # the line number here
   $self->{line} += ( $1 =~ tr/\n// ) if defined $1;
}

sub parse_ident
{
   my $self = shift;

   $self->skip_ws;

   return undef if $self->at_eos;

   $self->{str} =~ m/\G([\w.]+)/gc or
      $self->fail( "Expected identifier" );

   return $1;
}

sub parse_kw
{
   my $self = shift;
   my @acceptable = @_;

   $self->skip_ws;

   my $pos = pos $self->{str};

   defined( my $kw = $self->parse_ident ) or
      return undef;

   grep { $_ eq $kw } @acceptable or
      pos($self->{str}) = $pos, $self->fail( "Expected any of ".join( ", ", @acceptable ) );

   return $kw;
}

sub parse_string
{
   my $self = shift;

   $self->skip_ws;

   my $pos = pos $self->{str};

   $self->{str} =~ m/\G(["'])/gc or
      $self->fail( "Expected ' or \"" );

   my $delim = $1;

   $self->{str} =~ m/\G((?:\\.|[^\\])*)$delim/gc or
      pos($self->{str}) = $pos, $self->fail( "Expected contents of string" );

   my $string = $1;

   # TODO: Unescape stuff like \\ and \n and whatnot

   return $string;
}

sub fail
{
   my $self = shift;
   my ( $message ) = @_;

   my $pos = pos $self->{str};
   my $str = $self->{str};

   my $sol = $pos;
   $sol-- while $sol > 0 and substr( $str, $sol, 1 ) !~ m/^[\r\n]$/;

   my $eol = $pos;
   $eol++ while $eol < length($str) and substr( $str, $eol, 1 ) !~ m/^[\r\n]$/;

   my $line = substr( $str, $sol, $eol - $sol );
   my $col = $pos - $sol;

   die "$message on line $self->{line} at:\n$line\n" . 
       ( " " x ($col-1) . "^" ) . "\n";
}

sub enter_scope
{
   my $self = shift;
   my ( $start, $stop, $code ) = @_;

   ref $stop or $stop = qr/\Q$stop/;

   $self->expect( $start );
   local $self->{endofscope} = $stop;

   $code->();

   $self->expect( $stop );
}

sub at_eos
{
   my $self = shift;

   # DO NOT alter pos() here
   my $pos = pos $self->{str};

   return 1 if defined $pos and $pos >= length $self->{str};

   return 0 unless defined $self->{endofscope};

   my $at_eos = $self->{str} =~ m/\G$self->{endofscope}/;

   pos($self->{str}) = $pos;

   return $at_eos;
}

sub maybe
{
   my $self = shift;
   my ( $code ) = @_;

   my $pos = pos $self->{str};

   eval { $code->(); 1 } or pos($self->{str}) = $pos;
}

sub parse
{
   my $self = shift;

   my %package;

   while(1) {
      given( $self->parse_kw(qw( class include )) ) {
         when( undef ) {
            # EOF
            return \%package;
         }
         when( 'class' ) {
            my $classname = $self->parse_ident;

            exists $package{$classname} and
               $self->fail( "Already have a class called $classname" );

            $self->enter_scope( '{', '}', sub {
               $package{$classname} = $self->parse_classblock;
            } );
         }
         when( 'include' ) {
            my $filename = dirname($self->{filename}) . "/" . $self->parse_string;

            my $included = Tangence::Compiler::Parser->from_file( $filename );

            foreach my $classname ( keys %$included ) {
               exists $package{$classname} and
                  $self->fail( "Cannot include '$filename' as class $classname collides" );

               $package{$classname} = $included->{$classname};
            }
         }
         default {
            $self->fail( "Expected keyword, found $_" );
         }
      }
   }
}

sub parse_classblock
{
   my $self = shift;

   my %class;

   while(1) {
      given( $self->parse_kw(qw( method event prop smashed )) ) {
         when( undef ) {
            last;
         }

         when( 'method' ) {
            my $methodname = $self->parse_ident;

            exists $class{methods}{$methodname} and
               $self->fail( "Already have a method called $methodname" );

            my $mdef = $class{methods}{$methodname} = {};

            $self->enter_scope( '(', ')', sub {
               $mdef->{args} = $self->parse_typelist;
            } );

            $mdef->{ret} = "";

            $self->maybe( sub {
               $self->expect( '->' );

               $mdef->{ret} = $self->parse_type;
            } );
         }

         when( 'event' ) {
            my $eventname = $self->parse_ident;

            exists $class{events}{$eventname} and
               $self->fail( "Already have an event called $eventname" );

            my $edef = $class{events}{$eventname} = {};

            $self->enter_scope( '(', ')', sub {
               $edef->{args} = $self->parse_typelist;
            } );
         }

         my $smashed = 0;
         when( 'smashed' ) {
            $smashed = 1;

            $self->expect( 'prop' );

            $_ = 'prop'; continue; # goto case 'prop'
         }
         when( 'prop' ) {
            my $propname = $self->parse_ident;

            exists $class{props}{$propname} and
               $self->fail( "Already have a property called $propname" );

            my $pdef = $class{props}{$propname} = {};

            $pdef->{smash}++ if $smashed;

            $self->expect( '=' );

            my $dim = DIM_SCALAR;
            $self->maybe( sub {
               $dim = $self->parse_dim;
               $self->expect( 'of' );
            } );

            $pdef->{type} = $self->parse_type;

            $pdef->{dim} = $dim;
         }
      }

      $self->expect( ';' );
   }

   return \%class;
}

sub parse_typelist
{
   my $self = shift;

   my @ret;

   while(1) {
      push @ret, $self->parse_type;

      $self->skip_ws;
      $self->{str} =~ m/\G,/gc or last;
   }

   return \@ret;
}

my @basic_types = qw(
   bool
   int
   s8 s16 s32 s64 u8 u16 u32 u64
   str
   obj
   any
);

sub parse_type
{
   my $self = shift;

   my $typename = $self->parse_ident;

   grep { $_ eq $typename } @basic_types or
      $self->fail( "'$typename' is not a typename" );

   return $typename;
}

my %dimensions = (
   scalar => DIM_SCALAR,
   hash   => DIM_HASH,
   queue  => DIM_QUEUE,
   array  => DIM_ARRAY,
   objset => DIM_OBJSET,
);

sub parse_dim
{
   my $self = shift;

   my $dimname = $self->parse_kw( keys %dimensions );

   return $dimensions{$dimname};
}

1;
