var skip = [];

let keyboardHeatMapGenerator = {
    cmap:function(x){ // x between 0 and 1 (percentage)
	x = x * 255;
	r=255 ; g=255 ; b=255;
	if (x < 64) {
            r=0 ; g=x*4 ; b=255;
	} else if (x < 128) {
            r=0 ; g=255 ; b=(255-(x-64)*4);
	} else if (x < 192) {
            r=(x-128)*4 ; g=255  ;b = 0;
	} else if (x < 256) {
            r=255 ; g=(256-(x-191)*4) ; b=0;
	}
	return "rgb("+r+","+g+","+b+")";
    },
    compute:function(){
	console.log(this.id + ' xmp');
	var el = document.querySelector(this.id + ' xmp');
	//var el = $(this.id + ' xmp');
	this.totalCount = 0;
	for(var iShortcut=0; iShortcut < el.length; iShortcut++){
	    var str = el[iShortcut].innerHTML;
	    var count = parseInt(el[iShortcut].getAttribute('count'));
	    var cmds = str.replace('..', ',').split(',');
	    var alreadyCounted = {};
	    for(var iCmd = 0; iCmd < cmds.length; iCmd++){
		var keys = cmds[iCmd].split('-');
		for(var iKey = 0; iKey < keys.length; iKey++){
		    var subkeys = keys[iKey].split(' ');
		    for(var iSubKey = 0; iSubKey < subkeys.length; iSubKey++){
			var s=subkeys[iSubKey].replace(/[<>]/gi, '');
			if(s != "" && !skip.includes(s) && alreadyCounted[s] == undefined){
			    if(this.frequency[s] == undefined){
				this.frequency[s] = count;
			    }else{
				this.frequency[s] = this.frequency[s] + count;
			    }
			    alreadyCounted[s] = true;
			}
		    }
		}
	    }
	}
	
	for(var freqKey in this.frequency){
	    if (!skip.includes(freqKey) && this.keyboard.filter(item=>item.name.includes(freqKey)).length > 0) {
		this.totalCount = this.totalCount + this.frequency[freqKey];
		if (this.frequency[freqKey]>this.max_frequency) {
		    this.max_frequency = this.frequency[freqKey];
		}else if(this.frequency[freqKey]<this.min_frequency){
		    this.min_frequency = this.frequency[freqKey];
		}	
	    }
	    
	    
	}
    },
    draw:function(){
	this.context.clearRect(0,0,this.canvas.width, this.canvas.height);
	this.context.font=(this.u/4).toString() + "px Arial";
	var maxX = 0;
	var maxY = 0;
	for(var iKey=0; iKey < this.keyboard.length; iKey++){
	    const key = this.keyboard[iKey];
	    var freq = this.frequency[key.name]
	    this.context.fillStyle = this.cmap((freq - this.min_frequency) / (this.max_frequency - this.min_frequency));
	    this.context.fillRect(key.x * this.u, key.y * this.u, key.width * this.u, key.height * this.u);
	    this.context.strokeRect(key.x * this.u, key.y * this.u, key.width * this.u, key.height * this.u);
	    this.context.fillStyle = "black";
	    if (freq == undefined){
		this.context.fillText(key.name[0], (key.x + 0.25) * this.u, (key.y + 0.5) * this.u); 
	    }else{
		this.context.fillText(key.name[0], (key.x + 0.25) * this.u, (key.y + 0.5) * this.u); 
	    }
	    if (key.x + key.width> maxX) {
		maxX = key.x + key.width;
	    }
	    if (key.y + key.height> maxY) {
		maxY = key.y + key.height;
	    }
	    
	}

	for (var i = 0; i < 256; i++) {
	    this.context.fillStyle = this.cmap(1-i/256);
	    this.context.fillRect((maxX + 2) * this.u, this.u * i * maxY/256.0, this.u, this.u *(1.1)* maxY/256.0)
	}
	this.context.fillStyle = "black";
	this.context.font=(this.u/2).toString() + "px Arial";
	this.context.fillText(this.max_frequency.toString(), (maxX+3.2)*this.u, this.u/2);
	this.context.fillText(this.min_frequency.toString(), (maxX+3.2)*this.u, this.u * maxY);

    },
    init:function(id){
	this.id = '#' + id;
	this.canvas = document.getElementById('canvas-' + id);
	this.context = this.canvas.getContext('2d');
	this.frequency = {};
	this.max_frequency = 1;
	this.min_frequency = 0;
	this.totalCount = 0;
	this.u = 30;
	this.keyboard = [
	    // Top row
	    {name:['ESC'], x:0, y:0, width:1, height:1},
	    {name:['F1'], x:1.25, y:0, width:1, height:1},
	    {name:['F2'], x:2.25, y:0, width:1, height:1},
	    {name:['F3'], x:3.25, y:0, width:1, height:1},
	    {name:['F4'], x:4.25, y:0, width:1, height:1},
	    {name:['F5'], x:5.5, y:0, width:1, height:1},
	    {name:['F6'], x:6.5, y:0, width:1, height:1},
	    {name:['F7'], x:7.5, y:0, width:1, height:1},
	    {name:['F8'], x:8.5, y:0, width:1, height:1},
	    {name:['F9'], x:9.75, y:0, width:1, height:1},
	    {name:['F10'], x:10.75, y:0, width:1, height:1},
	    {name:['F11'], x:11.75, y:0, width:1, height:1},
	    {name:['F12'], x:12.75, y:0, width:1, height:1},
	    // First row
	    {name:['œ', 'Œ'], x:0, y:1.25, width:1, height:1},
	    {name:['&', '1'], x:1, y:1.25, width:1, height:1},
	    {name:['é', '2'], x:2, y:1.25, width:1, height:1},
	    {name:['"', '3'], x:3, y:1.25, width:1, height:1},
	    {name:['\'', '4'], x:4, y:1.25, width:1, height:1},
	    {name:['(', '5'], x:5, y:1.25, width:1, height:1},
	    {name:['-', '6'], x:6, y:1.25, width:1, height:1},
	    {name:['è', '7'], x:7, y:1.25, width:1, height:1},
	    {name:['_', '8'], x:8, y:1.25, width:1, height:1},
	    {name:['ç', '9'], x:9, y:1.25, width:1, height:1},
	    {name:['à', '10'], x:10, y:1.25, width:1, height:1},
	    {name:[')', '11'], x:11, y:1.25, width:1, height:1},
	    {name:['=', '12'], x:12, y:1.25, width:1, height:1},
	    {name:['backspace'], x:13, y:1.25, width:2, height:1},
	    // Second row
	    {name:['TAB'], x:0, y:2.25, width:1.25, height:1},
	    {name:['a'], x:1.25, y:2.25, width:1, height:1},
	    {name:['z'], x:2.25, y:2.25, width:1, height:1},
	    {name:['e'], x:3.25, y:2.25, width:1, height:1},
	    {name:['r'], x:4.25, y:2.25, width:1, height:1},
	    {name:['t'], x:5.25, y:2.25, width:1, height:1},
	    {name:['y'], x:6.25, y:2.25, width:1, height:1},
	    {name:['u'], x:7.25, y:2.25, width:1, height:1},
	    {name:['i'], x:8.25, y:2.25, width:1, height:1},
	    {name:['o'], x:9.25, y:2.25, width:1, height:1},
	    {name:['p'], x:10.25, y:2.25, width:1, height:1},
	    {name:['^'], x:11.25, y:2.25, width:1, height:1},
	    {name:['$'], x:12.25, y:2.25, width:1, height:1},
	    {name:['ENTER'], x:13.25, y:2.25, width:1.75, height:1},
	    // Third row
	    {name:['CAPSLOCK'], x:0, y:3.25, width:1.5, height:1},
	    {name:['q'], x:1.5, y:3.25, width:1, height:1},
	    {name:['s'], x:2.5, y:3.25, width:1, height:1},
	    {name:['d'], x:3.5, y:3.25, width:1, height:1},
	    {name:['f'], x:4.5, y:3.25, width:1, height:1},
	    {name:['g'], x:5.5, y:3.25, width:1, height:1},
	    {name:['h'], x:6.5, y:3.25, width:1, height:1},
	    {name:['j'], x:7.5, y:3.25, width:1, height:1},
	    {name:['k'], x:8.5, y:3.25, width:1, height:1},
	    {name:['l'], x:9.5, y:3.25, width:1, height:1},
	    {name:['m'], x:10.5, y:3.25, width:1, height:1},
	    {name:['ù'], x:11.5, y:3.25, width:1, height:1},
	    {name:['*'], x:12.5, y:3.25, width:1, height:1},
	    {name:['ENTER'], x:13.5, y:3.25, width:1.5, height:1},
	    // Fourth row
	    {name:['S'], x:0, y:4.25, width:1.25, height:1},
	    {name:['<'], x:1.25, y:4.25, width:1, height:1},
	    {name:['w'], x:2.25, y:4.25, width:1, height:1},
	    {name:['x'], x:3.25, y:4.25, width:1, height:1},
	    {name:['c'], x:4.25, y:4.25, width:1, height:1},
	    {name:['v'], x:5.25, y:4.25, width:1, height:1},
	    {name:['b'], x:6.25, y:4.25, width:1, height:1},
	    {name:['n'], x:7.25, y:4.25, width:1, height:1},
	    {name:[','], x:8.25, y:4.25, width:1, height:1},
	    {name:[';'], x:9.25, y:4.25, width:1, height:1},
	    {name:[':'], x:10.25, y:4.25, width:1, height:1},
	    {name:['!'], x:11.25, y:4.25, width:1, height:1},
	    {name:['RSHIFT'], x:12.25, y:4.25, width:2.75, height:1},
	    // Fifth row
	    {name:['C'], x:0, y:5.25, width:1.25, height:1},
	    {name:['LWIN'], x:1.25, y:5.25, width:1.25, height:1.5},
	    {name:['M'], x:2.5, y:5.25, width:1.25, height:1.5},
	    {name:['SPC'], x:3.75, y:5.25, width:6, height:1.5},
	    {name:['ALTGR'], x:9.75, y:5.25, width:1.25, height:1.5},
	    {name:['RWIN'], x:11, y:5.25, width:1.25, height:1.5},
	    {name:['menu'], x:12.25, y:5.25, width:1.25, height:1.5},
	    {name:['RCTRL'], x:13.5, y:5.25, width:1.5, height:1}
	];
    }
    
};
var update_skip = function(){
	var v = document.getElementById("skipkeys").value;
	if(v == ""){
	    skip = [];
	}else{
	    skip = eval(v);
	}
	keyboardHeatMapGenerator.init('major-modes');
	keyboardHeatMapGenerator.compute();
	keyboardHeatMapGenerator.draw();
	for (var iMode = 0; iMode < modes.length; iMode++) {
	    keyboardHeatMapGenerator.init(modes[iMode]);
	    keyboardHeatMapGenerator.compute();
	    keyboardHeatMapGenerator.draw();
	    
	}
    };
(function(){

    var generate_drawings = function(){
	keyboardHeatMapGenerator.init('major-modes');
	keyboardHeatMapGenerator.compute();
	keyboardHeatMapGenerator.draw();
	for (var iMode = 0; iMode < modes.length; iMode++) {
	    keyboardHeatMapGenerator.init(modes[iMode]);
	    keyboardHeatMapGenerator.compute();
	    keyboardHeatMapGenerator.draw();
	    
	}
    };
    
    $('body').append('<div style="position:fixed; top:0; right:50%; padding:20px;">' +
		     '<label for="skipkeys"> Skip keys: </label>' + 
		     '<input name="skipkeys" type="text" placeholder="Skip keys (e.g. [\'C\', \'S\', \'M\'])" id="skipkeys">' +
		     '<button onclick="update_skip()">OK</button>' + 
		     '</div>');
    generate_drawings();

})();


