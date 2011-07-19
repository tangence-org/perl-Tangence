package t::Conversation;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT = qw(
   %S2C
   %C2S

   $MSG_OK
);

our %S2C;
our %C2S;

our $MSG_OK = "\x80" . "\0\0\0\0";

# This module contains the string values used in various testing scripts that
# act as an example conversation between server and client. The strings are
# kept here in order to avoid mass duplication between the other testing
# modules, and to try to shield unwary visitors from the mass horror that is
# the following collection of large hex-encoded strings.

# If you are sitting comfortably, our story begings with the client...

# MSG_GETROOT
$C2S{GETROOT} = 
   "\x40" . "\0\0\0\x0b" .
   "\x2a" . "testscript";
$S2C{GETROOT} =
   "\x82" . "\0\0\0\xbe" .
   "\xe2" . "t::Bag\0" .
            "\x64" . "events\0"     . "\x61" . "destroy\0" . "\x61" . "args\0" . "\x40" .
                     "isa\0"        . "\x41" . "\x26" . "t::Bag" .
                     "methods\0"    . "\x63" . "add_ball\0"  . "\x62" . "args\0" . "\x41" . "\x23" . "obj" .
                                                                        "ret\0"  . "\x20" .
                                               "get_ball\0"  . "\x62" . "args\0" . "\x41" . "\x23" . "str" .
                                                                        "ret\0"  . "\x23" . "obj" .
                                               "pull_ball\0" . "\x62" . "args\0" . "\x41" . "\x23" . "str" .
                                                                        "ret\0"  . "\x23" . "obj" .
                     "properties\0" . "\x61" . "colours\0" . "\x62" . "dim\0"  . "\x21" . "2" .
                                                                      "type\0" . "\x23" . "int" .
            "\x40" .
   "\xe1" . "\0\0\0\1" . "t::Bag\0" . "\x40" .
   "\x84" . "\0\0\0\1";

# MSG_GETREGISTRY
$C2S{GETREGISTRY} =
   "\x41" . "\0\0\0\0";
$S2C{GETREGISTRY} =
   "\x82" . "\0\0\0\xe7" .
   "\xe2" . "Tangence::Registry\0" .
            "\x64" . "events\0"     . "\x63" . "destroy\0"            . "\x61" . "args\0" . "\x40" .
                                               "object_constructed\0" . "\x61" . "args\0" . "\x41" . "\x23" . "int" .
                                               "object_destroyed\0"   . "\x61" . "args\0" . "\x41" . "\x23" . "int" .
                     "isa\0"        . "\x41" . "\x32" . "Tangence::Registry" .
                     "methods\0"    . "\x61" . "get_by_id\0" . "\x62" . "args\0" . "\x41" . "\x23" . "int" .
                                                                        "ret\0"  . "\x23" . "obj" .
                     "properties\0" . "\x61" . "objects\0" . "\x62" . "dim\0"  . "\x21" . "2" .
                                                                      "type\0" . "\x23" . "str" .
            "\x40" .
   "\xe1" . "\0\0\0\0" . "Tangence::Registry\0" . "\x40" .
   "\x84" . "\0\0\0\0";

# MSG_CALL
$C2S{CALL_PULL} =
   "\1" . "\0\0\0\x10" . 
   "\x02" . "\x01" .
   "\x29" . "pull_ball" .
   "\x23" . "red";
# MSG_RESULT
$S2C{CALL_PULL} =
   "\x82" . "\0\0\0\xcf" .
   "\xe2" . "t::Ball\0" .
            "\x64" . "events\0"     . "\x62" . "bounced\0" . "\x61" . "args\0" . "\x41" . "\x23" . "str" .
                                               "destroy\0" . "\x61" . "args\0" . "\x40" .
                     "isa\0"        . "\x42" . "\x27" . "t::Ball" .
                                               "\x2d" . "t::Colourable" .
                     "methods\0"    . "\x61" . "bounce\0" . "\x62" . "args\0" . "\x41" . "\x23" . "str" .
                                                                     "ret\0" . "\x23" . "str" .
                     "properties\0" . "\x62" . "colour\0" . "\x62" . "dim\0" . "\x21" . "1" .
                                                                     "type\0" . "\x23" . "str" .
                                               "size\0"   . "\x63" . "dim\0" . "\x21" . "1" .
                                                                     "smash\0" . "\x21" . "1" .
                                                                     "type\0" . "\x23" . "int" .
            "\x41" . "\x24" . "size" .
   "\xe1" . "\0\0\0\2" . "t::Ball\0" . "\x41" . "\x23" . "100" .
   "\x84" . "\0\0\0\2";

$C2S{CALL_BOUNCE} =
   "\1" . "\0\0\0\x13" .
   "\x02" . "\x02" .
   "\x26" . "bounce" .
   "\x29" . "20 metres";
$S2C{CALL_BOUNCE} =
   "\x82" . "\0\0\0\x09" .
   "\x28" . "bouncing";

# MSG_SUBSCRIBE
$C2S{SUBSCRIBE_BOUNCED} =
   "\2" . "\0\0\0\x0a" .
   "\x02" . "\x02" .
   "\x27" . "bounced";
$S2C{SUBSCRIBE_BOUNCED} =
   "\x83" . "\0\0\0\0";

# MSG_EVENT
$S2C{EVENT_BOUNCED} =
   "\4" . "\0\0\0\x14" .
   "\x02" . "\x02" .
   "\x27" . "bounced" .
   "\x29" . "10 metres";
$S2C{EVENT_BOUNCED_5} =
   "\4" . "\0\0\0\x13" .
   "\x02" . "\x02" .
   "\x27" . "bounced" .
   "\x28" . "5 metres";

# MSG_GETPROP
$C2S{GETPROP_COLOUR} =
   "\5" . "\0\0\0\x09" .
   "\x02" . "\x02" .
   "\x26" . "colour";
$S2C{GETPROP_COLOUR_RED} =
   "\x82" . "\0\0\0\4" .
   "\x23" . "red";
$S2C{GETPROP_COLOUR_GREEN} =
   "\x82" . "\0\0\0\6" .
   "\x25" . "green";

# MSG_SETPROP
$C2S{SETPROP_COLOUR} =
   "\6" . "\0\0\0\x0e" .
   "\x02" . "\x02" .
   "\x26" . "colour" .
   "\x24" . "blue";

# MSG_WATCH
$C2S{WATCH_COLOUR} =
   "\7" . "\0\0\0\x0a" .
   "\x02" . "\x02" .
   "\x26" . "colour" .
   "\x00";
# MSG_WATCHING
$S2C{WATCH_COLOUR} =
   "\x84" . "\0\0\0\0";

# MSG_UPDATE
$S2C{UPDATE_COLOUR_ORANGE} =
   "\x09" . "\0\0\0\x12" .
   "\x02" . "\x02" .
   "\x26" . "colour" .
   "\x02" . "\x01" .
   "\x26" . "orange";
$S2C{UPDATE_COLOUR_YELLOW} =
   "\x09" . "\0\0\0\x12" .
   "\x02" . "\x02" .
   "\x26" . "colour" .
   "\x02" . "\x01" .
   "\x26" . "yellow";
$S2C{UPDATE_SIZE_200} =
   "\x09" . "\0\0\0\x0b" .
   "\x02" . "\x02" .
   "\x24" . "size" .
   "\x02" . "\x01" .
   "\x02" . "\xc8"; # 0xC8 == 200

# MSG_CALL
$C2S{CALL_ADD} =
   "\1" . "\0\0\0\x10" . 
   "\x02" . "\x01" .
   "\x28" . "add_ball" .
   "\x84" . "\0\0\0\2";
$S2C{CALL_ADD} =
   "\x82" . "\0\0\0\0";
$C2S{CALL_GET} = 
   "\1" . "\0\0\0\x12" .
   "\x02" . "\x01" .
   "\x28" . "get_ball" .
   "\x26" . "orange";
$S2C{CALL_GET} =
   "\x82" . "\0\0\0\5" .
   "\x84" . "\0\0\0\2";

# MSG_DESTROY
$S2C{DESTROY} = 
   "\x0a" . "\0\0\0\2" .
   "\x02" . "\x02";
