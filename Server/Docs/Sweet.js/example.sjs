console.log(isDefined(y));


function Foobar() {
	var self = this;
	
	self.x = 10;
	
	console.log(isDefined(y));
	console.log(isDefined(self.x));
}

module.exports = Foobar;
