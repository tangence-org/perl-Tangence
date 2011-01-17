package Tangence::Compiler::Parser;

use strict;
use warnings;

use base qw( Parser::MGC );

use feature qw( switch ); # we like given/when

use File::Basename qw( dirname );

use Tangence::Constants;

# Parsing is simpler if we treat Package.Name as a simple identifier
use constant pattern_ident => qr/[[:alnum:]_][\w.]*/;

sub parse
{
   my $self = shift;

   my %package;

   while( !$self->at_eos ) {
      given( $self->token_kw(qw( class include )) ) {
         when( 'class' ) {
            my $classname = $self->token_ident;

            exists $package{$classname} and
               $self->fail( "Already have a class called $classname" );

            $self->scope_of(
               '{', 
               sub { $package{$classname} = $self->parse_classblock },
               '}'
            );
         }
         when( 'include' ) {
            my $filename = dirname($self->{filename}) . "/" . $self->token_string;

            my $subparser = (ref $self)->new;
            my $included = $subparser->from_file( $filename );

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

   return \%package;
}

sub parse_classblock
{
   my $self = shift;

   my %class;

   while( !$self->at_eos ) {
      given( $self->token_kw(qw( method event prop smashed isa )) ) {
         when( 'method' ) {
            my $methodname = $self->token_ident;

            exists $class{methods}{$methodname} and
               $self->fail( "Already have a method called $methodname" );

            my $mdef = $class{methods}{$methodname} = {};

            $mdef->{args} = $self->parse_typelist;

            $mdef->{ret} = "";

            $self->maybe( sub {
               $self->expect( '->' );

               $mdef->{ret} = $self->parse_type;
            } );
         }

         when( 'event' ) {
            my $eventname = $self->token_ident;

            exists $class{events}{$eventname} and
               $self->fail( "Already have an event called $eventname" );

            my $edef = $class{events}{$eventname} = {};

            $edef->{args} = $self->parse_typelist;
         }

         my $smashed = 0;
         when( 'smashed' ) {
            $smashed = 1;

            $self->expect( 'prop' );

            $_ = 'prop'; continue; # goto case 'prop'
         }
         when( 'prop' ) {
            my $propname = $self->token_ident;

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

         when( 'isa' ) {
            my $supername = $self->token_ident;

            push @{ $class{isa} }, $supername;
         }
      }

      $self->expect( ';' );
   }

   return \%class;
}

sub parse_typelist
{
   my $self = shift;
   return $self->scope_of(
      "(",
      sub { $self->list_of( ",", \&parse_type ) },
      ")",
   );
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

   my $typename = $self->token_ident;

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

   my $dimname = $self->token_kw( keys %dimensions );

   return $dimensions{$dimname};
}

1;
