'use strict';

// https://www.npmjs.com/package/tracer

var logger = require('./Logger');
 
logger.log('hello');
logger.trace('hello', 'world');
logger.debug('hello %s',  'world', 123);
logger.info('hello %s %d',  'world', 123, {foo:'bar'});
logger.warn('hello %s %d %j', 'world', 123, {foo:'bar'});
logger.error('hello %s %d %j', 'world', 123, {foo:'bar'}, [1, 2, 3, 4], Object);

function MyFunc() {
}

MyFunc.prototype.myname = function() {
    logger.log('hello');
}

var x = new MyFunc();
x.myname();

