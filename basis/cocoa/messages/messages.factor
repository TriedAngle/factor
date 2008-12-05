! Copyright (C) 2006, 2008 Slava Pestov.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors alien alien.c-types alien.strings arrays assocs
combinators compiler compiler.alien kernel math namespaces make
parser prettyprint prettyprint.sections quotations sequences
strings words cocoa.runtime io macros memoize debugger
io.encodings.ascii effects libc libc.private parser lexer init
core-foundation fry generalizations
specialized-arrays.direct.alien ;
IN: cocoa.messages

: make-sender ( method function -- quot )
    [ over first , f , , second , \ alien-invoke , ] [ ] make ;

: sender-stub-name ( method function -- string )
    [ % "_" % unparse % ] "" make ;

: sender-stub ( method function -- word )
    [ sender-stub-name f <word> dup ] 2keep
    over first large-struct? [ "_stret" append ] when
    make-sender define ;

SYMBOL: message-senders
SYMBOL: super-message-senders

message-senders global [ H{ } assoc-like ] change-at
super-message-senders global [ H{ } assoc-like ] change-at

: cache-stub ( method function hash -- )
    [
        over get [ 2drop ] [ over [ sender-stub ] dip set ] if
    ] bind ;

: cache-stubs ( method -- )
    dup
    "objc_msgSendSuper" super-message-senders get cache-stub
    "objc_msgSend" message-senders get cache-stub ;

: <super> ( receiver -- super )
    "objc-super" <c-object> [
        [ dup object_getClass class_getSuperclass ] dip
        set-objc-super-class
    ] keep
    [ set-objc-super-receiver ] keep ;

TUPLE: selector name object ;

MEMO: <selector> ( name -- sel ) f \ selector boa ;

: selector ( selector -- alien )
    dup object>> expired? [
        dup name>> sel_registerName
        [ >>object drop ] keep
    ] [
        object>>
    ] if ;

SYMBOL: objc-methods

objc-methods global [ H{ } assoc-like ] change-at

: lookup-method ( selector -- method )
    dup objc-methods get at
    [ ] [ "No such method: " prepend throw ] ?if ;

MEMO: make-prepare-send ( selector method super? -- quot )
    [
        [ \ <super> , ] when
        swap <selector> , \ selector ,
    ] [ ] make
    swap second length 2 - '[ _ _ ndip ] ;

MACRO: (send) ( selector super? -- quot )
    [ dup lookup-method ] dip
    [ make-prepare-send ] 2keep
    super-message-senders message-senders ? get at
    '[ _ call _ execute ] ;

: send ( receiver args... selector -- return... ) f (send) ; inline

\ send soft "break-after" set-word-prop

: super-send ( receiver args... selector -- return... ) t (send) ; inline

\ super-send soft "break-after" set-word-prop

! Runtime introspection
SYMBOL: class-init-hooks

class-init-hooks global [ H{ } clone or ] change-at

: (objc-class) ( name word -- class )
    2dup execute dup [ 2nip ] [
        drop over class-init-hooks get at [ assert-depth ] when*
        2dup execute dup [ 2nip ] [
            2drop "No such class: " prepend throw
        ] if
    ] if ; inline

: objc-class ( string -- class )
    \ objc_getClass (objc-class) ;

: objc-protocol ( string -- class )
    \ objc_getProtocol (objc-class) ;

: objc-meta-class ( string -- class )
    \ objc_getMetaClass (objc-class) ;

SYMBOL: objc>alien-types

H{
    { "c" "char" }
    { "i" "int" }
    { "s" "short" }
    { "C" "uchar" }
    { "I" "uint" }
    { "S" "ushort" }
    { "f" "float" }
    { "d" "double" }
    { "B" "bool" }
    { "v" "void" }
    { "*" "char*" }
    { "?" "unknown_type" }
    { "@" "id" }
    { "#" "Class" }
    { ":" "SEL" }
}
"ptrdiff_t" heap-size {
    { 4 [ H{
        { "l" "long" }
        { "q" "longlong" }
        { "L" "ulong" }
        { "Q" "ulonglong" }
    } ] }
    { 8 [ H{
        { "l" "long32" }
        { "q" "long" }
        { "L" "ulong32" }
        { "Q" "ulong" }
    } ] }
} case
assoc-union objc>alien-types set-global

! The transpose of the above map
SYMBOL: alien>objc-types

objc>alien-types get [ swap ] assoc-map
! A hack...
"ptrdiff_t" heap-size {
    { 4 [ H{
        { "NSPoint"    "{_NSPoint=ff}" }
        { "NSRect"     "{_NSRect={_NSPoint=ff}{_NSSize=ff}}" }
        { "NSSize"     "{_NSSize=ff}" }
        { "NSRange"    "{_NSRange=II}" }
        { "NSInteger"  "i" }
        { "NSUInteger" "I" }
        { "CGFloat"    "f" }
    } ] }
    { 8 [ H{
        { "NSPoint"    "{CGPoint=dd}" }
        { "NSRect"     "{CGRect={CGPoint=dd}{CGSize=dd}}" }
        { "NSSize"     "{CGSize=dd}" }
        { "NSRange"    "{_NSRange=QQ}" }
        { "NSInteger"  "q" }
        { "NSUInteger" "Q" }
        { "CGFloat"    "d" }
    } ] }
} case
assoc-union alien>objc-types set-global

: objc-struct-type ( i string -- ctype )
    [ CHAR: = ] 2keep index-from swap subseq
    dup c-types get key? [
        "Warning: no such C type: " write dup print
        drop "void*"
    ] unless ;

: (parse-objc-type) ( i string -- ctype )
    [ [ 1+ ] dip ] [ nth ] 2bi {
        { [ dup "rnNoORV" member? ] [ drop (parse-objc-type) ] }
        { [ dup CHAR: ^ = ] [ 3drop "void*" ] }
        { [ dup CHAR: { = ] [ drop objc-struct-type ] }
        { [ dup CHAR: [ = ] [ 3drop "void*" ] }
        [ 2nip 1string objc>alien-types get at ]
    } cond ;

: parse-objc-type ( string -- ctype ) 0 swap (parse-objc-type) ;

: method-arg-type ( method i -- type )
    method_copyArgumentType
    [ ascii alien>string parse-objc-type ] keep
    (free) ;

: method-arg-types ( method -- args )
    dup method_getNumberOfArguments
    [ method-arg-type ] with map ;

: method-return-type ( method -- ctype )
    method_copyReturnType
    [ ascii alien>string parse-objc-type ] keep
    (free) ;

: register-objc-method ( method -- )
    dup method-return-type over method-arg-types 2array
    dup cache-stubs
    swap method_getName sel_getName
    objc-methods get set-at ;

: each-method-in-class ( class quot -- )
    [ 0 <uint> [ class_copyMethodList ] keep *uint ] dip
    over 0 = [ 3drop ] [
        [ <direct-void*-array> ] dip
        [ each ] [ drop underlying>> (free) ] 2bi
    ] if ; inline

: register-objc-methods ( class -- )
    [ register-objc-method ] each-method-in-class ;

: method. ( method -- )
    {
        [ method_getName sel_getName ]
        [ method-return-type ]
        [ method-arg-types ]
        [ method_getImplementation ]
    } cleave 4array . ;

: methods. ( class -- )
    [ method. ] each-method-in-class ;

: class-exists? ( string -- class ) objc_getClass >boolean ;

: define-objc-class-word ( quot name -- )
    [ class-init-hooks get set-at ]
    [
        [ "cocoa.classes" create ] [ '[ _ objc-class ] ] bi
        (( -- class )) define-declared
    ] bi ;

: import-objc-class ( name quot -- )
    over define-objc-class-word
    '[
        _
        [ objc-class register-objc-methods ]
        [ objc-meta-class register-objc-methods ] bi
    ] try ;

: root-class ( class -- root )
    dup class_getSuperclass [ root-class ] [ ] ?if ;
