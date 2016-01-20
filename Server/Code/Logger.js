// Output logging.
// I've put this in a separate file in case I want to start logging to a file.
// See examples at: // https://www.npmjs.com/package/tracer

var logger = require('tracer').colorConsole();

'use strict';

// export the class
module.exports = logger;
