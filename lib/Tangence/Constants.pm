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
   DIM_QUEUE

   CHANGE_SET
   CHANGE_ADD
   CHANGE_DEL
   CHANGE_PUSH
   CHANGE_SHIFT
);

# Message types

# Requests

use constant MSG_CALL => 0x01;
# call a method: $objpath, $method, @args -> ERROR / RESULT
use constant MSG_SUBSCRIBE => 0x02;
# subscribe to an event: $objpath, $event -> ERROR / SUBSCRIBED
use constant MSG_UNSUBSCRIBE => 0x03;
# cancel a MSG_SUBSCRIBE: $objpath, $event, $id -> ERROR / OK
use constant MSG_EVENT => 0x04;
# notification of an event: $objpath, $event, @args -> ERROR / OK
use constant MSG_GETPROP => 0x05;
# get the value of a property: $objpath, $prop -> ERROR / RESULT
use constant MSG_SETPROP => 0x06;
# set the value of a property: $objpath, $prop, $value -> ERROR / OK
use constant MSG_WATCH => 0x07;
# watch a property for changes: $objpath, $prop, $want_initial -> ERROR / WATCHING
use constant MSG_UNWATCH => 0x08;
# cancel a MSG_WATCH: $objpath, $prop, $id -> ERROR / OK
use constant MSG_UPDATE => 0x09;
# notification of a property value change: $prop, $how, @value -> ERROR / OK

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
use constant DIM_QUEUE  => 4; # top-gravity list;

# Property change types
use constant CHANGE_SET   => 1; # ALL: New value follows
use constant CHANGE_ADD   => 2; # HASH: New key/value pair follows
use constant CHANGE_DEL   => 3; # HASH: Deleted key follows
use constant CHANGE_PUSH  => 4; # ARRAY/QUEUE: New members follow in a list
use constant CHANGE_SHIFT => 5; # QUEUE: Count of old elements to remove

1;
