! Copyright (C) 2007, 2008 Chris Double, Doug Coleman.
! See http://factorcode.org/license.txt for BSD license.
USING: kernel sequences strings namespaces math assocs shuffle 
     vectors arrays combinators.lib memoize math.parser match
     unicode.categories sequences.deep peg peg.private ;
IN: peg.parsers

TUPLE: just-parser p1 ;

: just-pattern
  [
    dup [
      dup parse-result-remaining empty? [ drop f ] unless
    ] when
  ] ;


M: just-parser compile ( parser -- quot )
  just-parser-p1 compile just-pattern append ;

MEMO: just ( parser -- parser )
  just-parser construct-boa init-parser ;

MEMO: 1token ( ch -- parser ) 1string token ;

<PRIVATE
MEMO: (list-of) ( items separator repeat1? -- parser )
  >r over 2seq r> [ repeat1 ] [ repeat0 ] if [ concat ] action 2seq
  [ unclip 1vector swap first append ] action ;
PRIVATE>

MEMO: list-of ( items separator -- parser )
  hide f (list-of) ;

MEMO: list-of-many ( items separator -- parser )
  hide t (list-of) ;

MEMO: epsilon ( -- parser ) V{ } token ;

MEMO: any-char ( -- parser ) [ drop t ] satisfy ;

<PRIVATE

: flatten-vectors ( pair -- vector )
  first2 over push-all ;

PRIVATE>

MEMO: exactly-n ( parser n -- parser' )
  swap <repetition> seq ;

MEMO: at-most-n ( parser n -- parser' )
  dup zero? [
    2drop epsilon
  ] [
    2dup exactly-n
    -rot 1- at-most-n 2choice
  ] if ;

MEMO: at-least-n ( parser n -- parser' )
  dupd exactly-n swap repeat0 2seq
  [ flatten-vectors ] action ;

MEMO: from-m-to-n ( parser m n -- parser' )
  >r [ exactly-n ] 2keep r> swap - at-most-n 2seq
  [ flatten-vectors ] action ;

MEMO: pack ( begin body end -- parser )
  >r >r hide r> r> hide 3seq [ first ] action ;

MEMO: surrounded-by ( parser begin end -- parser' )
  [ token ] 2apply swapd pack ;

MEMO: 'digit' ( -- parser )
  [ digit? ] satisfy [ digit> ] action ;

MEMO: 'integer' ( -- parser )
  'digit' repeat1 [ 10 digits>integer ] action ;

MEMO: 'string' ( -- parser )
  [
    [ CHAR: " = ] satisfy hide ,
    [ CHAR: " = not ] satisfy repeat0 ,
    [ CHAR: " = ] satisfy hide ,
  ] { } make seq [ first >string ] action ;
