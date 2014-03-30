#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013-2014 -- leonerd@leonerd.org.uk

package Tangence::Type;

use strict;
use warnings;

use base qw( Tangence::Meta::Type );

require Tangence::Type::Primitive;

sub new
{
   # Subtle trickery is at work here
   # Invoke our own superclass constructor, but pretend to be some higher
   # subclass that's appropriate

   shift;
   if( @_ == 1 ) {
      my ( $type ) = @_;
      my $class = "Tangence::Type::Primitive::$type";
      $class->can( "new" ) or die "TODO: Need $class";

      return $class->SUPER::new( $type );
   }
   elsif( $_[0] eq "list" ) {
      shift;
      return Tangence::Type::List->SUPER::new( list => @_ );
   }
   elsif( $_[0] eq "dict" ) {
      shift;
      return Tangence::Type::Dict->SUPER::new( dict => @_ );
   }
   else {
      die "TODO: Not sure how to make a Tangence::Type->new( @_ )";
   }
}

package
   Tangence::Type::List;
use base qw( Tangence::Type );

sub default_value { [] }

package
   Tangence::Type::Dict;
use base qw( Tangence::Type );

sub default_value { {} }

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
