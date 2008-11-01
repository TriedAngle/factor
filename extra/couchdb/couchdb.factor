! Copyright (C) 2008 Alex Chapman
! See http://factorcode.org/license.txt for BSD license.
USING: accessors arrays assocs continuations debugger hashtables http http.client io json.reader json.writer kernel make math math.parser namespaces sequences strings urls vectors ;
IN: couchdb

! NOTE: This code only works with the latest couchdb (0.9.*), because old
! versions didn't provide the /_uuids feature which this code relies on when
! creating new documents.

SYMBOL: couch
: with-couch ( db quot -- )
    couch swap with-variable ; inline

! errors
TUPLE: couchdb-error { data assoc } ;
C: <couchdb-error> couchdb-error

M: couchdb-error error. ( error -- )
    "CouchDB Error: " write data>>
    "error" over at [ print ] when*
    "reason" swap at [ print ] when* ;

PREDICATE: file-exists-error < couchdb-error
    data>> "error" swap at "file_exists" = ;

! http tools
: couch-http-request ( request -- data )
    [ http-request ] [
        dup download-failed? [
            data>> json> <couchdb-error> throw
        ] [
            rethrow
        ] if
    ] recover nip ;

: couch-request ( request -- assoc )
    couch-http-request json> ;

: couch-get ( url -- assoc )
    <get-request> couch-request ;

: couch-put ( post-data url -- assoc )
    <put-request> couch-request ;

: couch-post ( post-data url -- assoc )
    <post-request> couch-request ;

: couch-delete ( url -- assoc )
    <delete-request> couch-request ;

: response-ok ( assoc -- assoc )
    "ok" over delete-at* and t assert= ;

: response-ok* ( assoc -- )
    response-ok drop ;

! server
TUPLE: server { host string } { port integer } { uuids vector } { uuids-to-cache integer } ;

: default-couch-host "localhost" ;
: default-couch-port 5984 ;
: default-uuids-to-cache 100 ;

: <server> ( host port -- server )
    V{ } clone default-uuids-to-cache server boa ;

: <default-server> ( -- server )
    default-couch-host default-couch-port <server> ;

: (server-url) ( server -- )
    "http://" % [ host>> % ] [ CHAR: : , port>> number>string % ] bi CHAR: / , ; inline

: server-url ( server -- url )
    [ (server-url) ] "" make ;

: all-dbs ( server -- dbs )
    server-url "_all_dbs" append couch-get ;

: uuids-url ( server -- url )
    [ dup server-url % "_uuids?count=" % uuids-to-cache>> number>string % ] "" make ;

: uuids-post ( server -- uuids )
     uuids-url f swap couch-post "uuids" swap at >vector ;

: get-uuids ( server -- server )
    dup uuids-post [ nip ] curry change-uuids ;

: ensure-uuids ( server -- server )
    dup uuids>> empty? [ get-uuids ] when ;

: next-uuid ( server -- uuid )
    ensure-uuids uuids>> pop ;

! db 
TUPLE: db { server server } { name string } ;
C: <db> db

: (db-url) ( db -- )
    [ server>> server-url % ] [ name>> % ] bi CHAR: / , ; inline

: db-url ( db -- url )
    [ (db-url) ] "" make ;

: create-db ( db -- )
    f swap db-url couch-put response-ok* ;

: ensure-db ( db -- )
    [ create-db ] [
        dup file-exists-error? [ 2drop ] [ rethrow ] if
    ] recover ;

: delete-db ( db -- )
    db-url couch-delete drop ;

: db-info ( db -- info )
    db-url couch-get ;

: compact-db ( db -- )
    f swap db-url "_compact" append couch-post response-ok* ;

: all-docs ( db -- docs )
    ! TODO: queries. Maybe pass in a hashtable with options
    db-url "_all_docs" append couch-get ;

: <json-post-data> ( assoc -- post-data )
    >json "application/json" <post-data> ;

! documents
: id> ( assoc -- id ) "_id" swap at ; 
: >id ( assoc id -- assoc ) "_id" pick set-at ;
: rev> ( assoc -- rev ) "_rev" swap at ;
: >rev ( assoc rev -- assoc ) "_rev" pick set-at ;

: copy-key ( to from to-key from-key -- )
    rot at spin set-at ;

: copy-id ( to from -- )
    "_id" "id" copy-key ;

: copy-rev ( to from -- )
    "_rev" "rev" copy-key ;

: id-url ( id -- url )
    couch get db-url swap append ;

: doc-url ( assoc -- url )
    id> id-url ;

: new-doc-url ( -- url )
    couch get [ db-url ] [ server>> next-uuid ] bi append ;

: save-new ( assoc -- )
    dup <json-post-data> new-doc-url couch-put response-ok
    [ copy-id ] [ copy-rev ] 2bi ;

: save-existing ( assoc id -- )
    [ dup <json-post-data> ] dip id-url couch-put response-ok copy-rev ;

: save ( assoc -- )
    dup id> [ save-existing ] [ save-new ] if* ; 

: load ( id -- assoc )
    id-url couch-get ;

: delete ( assoc -- )
    [
        [ doc-url % ]
        [ "?rev=" % "_rev" swap at % ] bi
    ] "" make couch-delete response-ok* ;

: remove-keys ( assoc keys -- )
    swap [ delete-at ] curry each ;

: remove-couch-info ( assoc -- )
    { "_id" "_rev" "_attachments" } remove-keys ;

! TODO:
! - startkey, count, descending, etc.
! - loading specific revisions
! - views
! - attachments
! - bulk insert/update
! - ...?
