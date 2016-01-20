// Sweet macros
// Files using these macros have to be named with a .sjs extension, or the require doesn't seem to process them correctly.
// I had to install sweet using:
// npm install --save-dev
// See: https://www.npmjs.com/package/sweetbuild
// Followed instructions from https://github.com/mozilla/sweet.js/wiki/node-loader

// Initially I just had "($x)" in the macro below. But this failed to match with 
// expressions such as "self.x. Adding the :expr qualifier cures things. See
// http://jlongster.com/Writing-Your-First-Sweet.js-Macro

// Also see my writeup at http://stackoverflow.com/questions/13335873/how-to-check-if-a-variable-is-defined-or-not/34102863#34102863 

macro isDefined {
  rule {
    ($x:expr)
  } => {
  	(( typeof ($x) === 'undefined' || ($x) === null) ? false : true)
  }
}

/* 
This macro is for development only, not production. Inject errors for testing. If $x is not null, or the test case is present, returns true.
The "Error test case" part of this is a hack. I wanted to have the $error variable set to "Error test case" (i.e., make it really non-null) when we had our debugTestCase being true. And this works. It deals with three cases properly: (1) $error is non-null, then the value of $error is not changed; (2) debugTestCase is not the specificTestCase, then the value of $error is unchanged, and (3) $error is null, and debugTestCase is the specificTestCase, then the value of $error is changed to "Error test case". Here are the test cases:

var op = {};

var error = new Error();
op.debugTestCase = 2;
if (objOrInject(error, op, 1)) {
    console.log("error (expect Error object): " + error + "\n");
}

var error = null;
op.debugTestCase = 2;
if (objOrInject(error, op, 1)) {
    console.log("Yikes: Shouldn't get any output here!\n");
}

var error = null;
op.debugTestCase = 1;
if (objOrInject(error, op, 1)) {
    console.log("error: (expect 'Error test case'): " + error + "\n");
}

I did initial debugging of this with: http://sweetjs.org/browser/editor.html
*/
macro objOrInject {
  rule {
    ($error:expr, $op:expr, $specificTestCase:expr)
  } => {
    ((($error) !== null) ?
        true :
        ((($op).debugTestCase == ($specificTestCase)) ?
            ($error = "Error test case", true) : false
        )
    )
  }
}

// Seems the macros have to be exported
// https://github.com/mozilla/sweet.js/wiki/modules

export isDefined;
export objOrInject;
