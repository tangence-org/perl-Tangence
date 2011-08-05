#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Metacode;

use strict;
use warnings;

our $VERSION = '0.07';

use Carp;

use Tangence::Constants;
use Tangence::Meta::Class;

sub init_class
{
   my $class = shift;

   my $meta = Tangence::Meta::Class->for_perlname( $class );

   foreach my $superclass ( $meta->direct_superclasses ) {
      my $name = $superclass->name;
      init_class( $name ) unless defined &{"${name}::_has_Tangence"};
   }

   my %subs = (
      _has_Tangence => sub() { 1 },
   );

   my $props = $meta->properties;

   foreach my $prop ( keys %$props ) {
      my $pdef = $props->{$prop};

      $pdef->build_subs( \%subs );
   }

   no strict 'refs';

   foreach my $name ( keys %subs ) {
      next if defined &{"${class}::${name}"};
      *{"${class}::${name}"} = $subs{$name};
   }
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
