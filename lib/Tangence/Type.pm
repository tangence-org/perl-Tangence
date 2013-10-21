#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Tangence::Type;

use strict;
use warnings;
use feature qw( switch );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use base qw( Tangence::Meta::Type );

sub default_value
{
   my $self = shift;

   given( $self->aggregate ) {
      when( "prim" ) {
         given( $self->sig ) {
            when( "bool" ) {
               return "";
            }
            when( [ "int", "u8", "s8", "u16", "s16", "u32", "s32", "u64", "s64" ] ) {
               return 0;
            }
            when( "str" ) {
               return "";
            }
            when( "obj" ) {
               return undef;
            }
            when( "any" ) {
               return undef;
            }
            default { die "TODO: unknown prim signature $_" }
         }
      }
      when( "list" ) { return [] }
      when( "dict" ) { return {} }
      default { die "TODO: unknown aggregate $_" }
   }
}

0x55AA;
