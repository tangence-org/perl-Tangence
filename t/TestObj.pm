package t::TestObj;

use strict;

use base qw( Tangence::Object );

use Tangence::Constants;

our %PROPS = (
   scalar => {
      dim  => DIM_SCALAR,
      type => 'int',
   },

   hash => {
      dim  => DIM_HASH,
      type => 'int',
   },

   array => {
      dim  => DIM_ARRAY,
      type => 'int',
   },
);

sub new
{
   my $class = shift;

   my $self = $class->SUPER::new( @_ );

   $self->{scalar} = "123";
   $self->{hash}   = { one => 1, two => 2, three => 3 };
   $self->{array}  = [ 1, 2, 3 ];

   return $self;
}

sub get_prop_scalar
{
   my $self = shift;
   return $self->{scalar};
}

sub get_prop_hash
{
   my $self = shift;
   return $self->{hash};
}

sub get_prop_array
{
   my $self = shift;
   return $self->{array};
}

sub add_number
{
   my $self = shift;
   my ( $name, $num ) = @_;

   if( index( $self->{scalar}, $num ) == -1 ) {
      $self->{scalar} .= $num;
      $self->update_property( "scalar", CHANGE_SET, $self->{scalar} );
   }

   $self->{hash}->{$name} = $num;
   $self->update_property( "hash", CHANGE_ADD, $name, $num );

   if( !grep { $_ == $num } @{ $self->{array} } ) {
      push @{ $self->{array} }, $num;
      $self->update_property( "array", CHANGE_PUSH, $num );
   }
}

sub del_number
{
   my $self = shift;
   my ( $num ) = @_;

   my $name;
   $self->{hash}->{$_} == $num and ( $name = $_, last ) for keys %{ $self->{hash} };

   defined $name or die "No name for $num";

   if( index( $self->{scalar}, $num ) != -1 ) {
      $self->{scalar} =~ s/\Q$num//;
      $self->update_property( "scalar", CHANGE_SET, $self->{scalar} );
   }

   delete $self->{hash}->{$name};
   $self->update_property( "hash", CHANGE_DEL, $name );

   if( grep { $_ == $num } @{ $self->{array} } ) {
      my $index;
      $self->{array}->[$_] == $num and ( $index = $_, last ) for 0 .. $#{ $self->{array} };
      splice @{ $self->{array} }, $index, 1, ();
      $self->update_property( "array", CHANGE_SPLICE, $index, 1, () );
   }
}

1;
