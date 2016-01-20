var sweet = require('sweet.js');

// load all exported macros in `macros/str.sjs`
sweet.loadMacro('./macros.sjs');

// example.sjs uses macros that have been defined and exported in `macros.sjs`
var Foobar = require('./example.sjs');

var x = new Foobar();
