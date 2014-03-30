#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013-2014 -- leonerd@leonerd.org.uk

package Tangence::Type::Primitive;

use strict;
use warnings;
use feature qw( switch );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use base qw( Tangence::Type );

package
   Tangence::Type::Primitive::bool;
use base qw( Tangence::Type::Primitive );

sub default_value { "" }

package
   Tangence::Type::Primitive::_integral;
use base qw( Tangence::Type::Primitive );

sub default_value { 0 }

package
   Tangence::Type::Primitive::u8;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::s8;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::u16;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::s16;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::u32;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::s32;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::u64;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::s64;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::int;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::str;
use base qw( Tangence::Type::Primitive );

sub default_value { "" }

package
   Tangence::Type::Primitive::obj;
use base qw( Tangence::Type::Primitive );

sub default_value { undef }

package
   Tangence::Type::Primitive::any;
use base qw( Tangence::Type::Primitive );

sub default_value { undef }

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
