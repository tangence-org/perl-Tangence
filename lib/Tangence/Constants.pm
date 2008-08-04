package Tangence::Constants;

use strict;

use base qw( Exporter );
our @EXPORT = qw(
   MSG_CALL
   MSG_SUBSCRIBE
   MSG_UNSUBSCRIBE
   MSG_EVENT
   MSG_GETPROP
   MSG_SETPROP
   MSG_WATCH
   MSG_UNWATCH
   MSG_UPDATE

   MSG_OK
   MSG_ERROR
   MSG_RESULT
   MSG_SUBSCRIBED
   MSG_WATCHING

   DIM_SCALAR
   DIM_HASH
   DIM_ARRAY
   DIM_OBJSET

   CHANGE_SET
   CHANGE_ADD
   CHANGE_DEL
   CHANGE_PUSH
   CHANGE_SHIFT
   CHANGE_SPLICE

   DATA_UNDEF
   DATA_STRING
   DATA_LIST
   DATA_DICT
   DATA_OBJECT

   DATATYPE_CONSTRUCT
   DATATYPE_CLASS
);

# Message types

# Requests

use constant MSG_CALL => 0x01;
# call a method: $objid, $method, @args -> ERROR / RESULT
use constant MSG_SUBSCRIBE => 0x02;
# subscribe to an event: $objid, $event -> ERROR / SUBSCRIBED
use constant MSG_UNSUBSCRIBE => 0x03;
# cancel a MSG_SUBSCRIBE: $objid, $event, $id -> ERROR / OK
use constant MSG_EVENT => 0x04;
# notification of an event: $objid, $event, @args -> ERROR / OK
use constant MSG_GETPROP => 0x05;
# get the value of a property: $objid, $prop -> ERROR / RESULT
use constant MSG_SETPROP => 0x06;
# set the value of a property: $objid, $prop, $value -> ERROR / OK
use constant MSG_WATCH => 0x07;
# watch a property for changes: $objid, $prop, $want_initial -> ERROR / WATCHING
use constant MSG_UNWATCH => 0x08;
# cancel a MSG_WATCH: $objid, $prop, $id -> ERROR / OK
use constant MSG_UPDATE => 0x09;
# notification of a property value change: $objid, $prop, $how, @value -> ERROR / OK

# Responses

use constant MSG_OK => 0x80;
# simple response with no further meaning
use constant MSG_ERROR => 0x81;
# result is an error message: $message
use constant MSG_RESULT => 0x82;
# result of a method call or property get: @values
use constant MSG_SUBSCRIBED => 0x83;
# result of MSG_SUBSCRIBE: $id
use constant MSG_WATCHING => 0x84;
# result of MSG_WATCH: $id, $dim


# Property dimensions
use constant DIM_SCALAR => 1;
use constant DIM_HASH   => 2;
use constant DIM_ARRAY  => 3;
use constant DIM_OBJSET => 4; # set of objects (implemented like id-keyed list in no particular order)

# Property change types
use constant CHANGE_SET    => 1; # SCALAR/HASH/ARRAY: New value follows. OBJSET: LIST of objects follows
use constant CHANGE_ADD    => 2; # HASH: New key/value pair follows, OBJSET: New object follows
use constant CHANGE_DEL    => 3; # HASH: Deleted key follows, OBJSET: Deleted id follows
use constant CHANGE_PUSH   => 4; # ARRAY: New members follow in a list
use constant CHANGE_SHIFT  => 5; # ARRAY: Count of old elements to remove
use constant CHANGE_SPLICE => 6; # ARRAY: Start index, count, [ new elements ]

# Stream data types
use constant DATA_UNDEF  => 0; # Undefinedness
use constant DATA_STRING => 1; # String: num(length) . octets
use constant DATA_LIST   => 2; # List: num(elements) . value0 . value1...
use constant DATA_DICT   => 3; # Dictionary: num(pairs) . key0 . value0 . key1 . value1...
use constant DATA_OBJECT => 4; # Object: objid

use constant DATATYPE_CONSTRUCT => 0x81; # Construct: num(id), typenameZ
use constant DATATYPE_CLASS     => 0x82; # Class: typenameZ, schema

1;
