//2023 @Jacques Brocard for Sandrine Bretaud (IGFL)

var dir //Name of the directory of original images of axons + contour ROI
max_intens=2048; //Maxium intensity used for 8-bit conversion, line 168
dir = getDirectory( "Choose a directory of MIP images with a contoured axon" );
set_IO(dir+File.separator+"sSTR"); //checks or creates a result directory sSTR
set_IO(dir+File.separator+"sMASK"); //checks or creates a result directory sMASK
set_IO(dir+File.separator+"sLOG"); //checks or creates a result directory sLOG

if (isOpen("Log")) {
	selectWindow("Log");
	run("Close");
}
roiManager("Reset");

//--- INITIALIZATION of PARAMETERS
setBatchMode(true);
list = getFileList(dir);
iWidth=newArray(list.length);
iHeight=newArray(list.length);
setLineWidth(1);
for (i=0; i<list.length; i++){
	ext=substring(list[i],lengthOf(list[i])-4,lengthOf(list[i]));
    if ((ext==".tif")){
    	//From every .tif image, extract pixel data and axonal length
		roiManager("Reset");
		open(dir+list[i]);
		getPixelSize(unit, pixelWidth, pixelHeight);
		run("Properties...", "channels=1 slices=1 frames=1 pixel_width=1 pixel_height=1 voxel_depth=1.0000000");
		iHeight[i]=getHeight();
		iWidth[i]=getWidth();
		close();
    }
}
Array.getStatistics(iWidth, min, sWidth);
//Width in units, a multiple of 5 
sWidth=sWidth*pixelWidth/2;
sWidth=5*floor(sWidth/5);
//print(sWidth+ " " + unit);
Array.getStatistics(iHeight, min, sHeight);
//Height in units, a multiple of 10
sHeight=sHeight*pixelWidth;
sHeight=10*floor(1+sHeight/10);
//print(sHeight+ " " + unit);	
setBatchMode(false);


h=0; miniHeight=0;
while (sWidth <1 || h<sHeight || miniHeight>sHeight){
	//Dialog box for parameter initialization
	Dialog.create("Initialization");
	Dialog.addNumber("Width ("+unit+") = ",sWidth);
	Dialog.addNumber("Max height ("+unit+") <= ",sHeight);
	Dialog.addNumber("Min height ("+unit+") >= ",miniHeight);
	Dialog.show();
	sWidth=Dialog.getNumber();
	h=Dialog.getNumber();
	miniHeight=Dialog.getNumber();
}

sWidth=floor(sWidth/pixelWidth);
sHeight=10*floor(h/pixelHeight/10);


//--- STRAIGHTENING and AXON LENGTH measurement
print(dir);
print("Min. length = " + miniHeight + " " + unit);
miniHeight=floor(miniHeight/pixelWidth);
print("1 pixel = "+ pixelWidth + " " + unit);
print("Axonal lengths (pixels)");
length=newArray();
nb_images=0;
for (i=0; i<list.length; i++){
	ext=substring(list[i],lengthOf(list[i])-4,lengthOf(list[i]));
    if ((ext==".tif")){
    	//Extract axonal length from each .tif image
		t=list[i];
		roiManager("Reset");
		open(dir+t);
		roiManager("Add");
		roiManager("Select",0);
		run("Properties...", "channels=1 slices=1 frames=1 pixel_width=1 pixel_height=1 voxel_depth=1.0000000");
		getStatistics(area);
		if (area>miniHeight){
			print(list[i] +  " \t"+area);
			length[nb_images]=area;
			nb_images++;
		}
	
		//Straighten original image
		roiManager("Set Line Width", sWidth);
		run("Straighten...");
		rename("str"); 
		run("Rotate 90 Degrees Right");
		run("Select All");
		saveAs("Tiff", dir+"sSTR/"+substring(t,0,lengthOf(t)-4)+"_str.tif");
		rename("count"); 
		
		//Keep the regions with no signal (=NaN) to subtract from the MASK image,
		//in order to avoid edge detection artifacts
		run("Duplicate...", "title=NaN");
		setThreshold(0,0);
		setOption("BlackBackground", true);
		run("Convert to Mask");
		run("Grays");
		run("Options...", "iterations=2 count=1 black do=Dilate");
		close(t);
	
		//Automatic detection of axon + neurites
		selectWindow("count"); 
		run("Square Root");
		run("Subtract Background...", "rolling=2");
		setAutoThreshold("Default dark");
		setThreshold(1.0000, 1000000000000000000000000000000.0000);
		setOption("BlackBackground", true);
		run("Convert to Mask");
		run("Skeletonize (2D/3D)");
	
		//Keep only neurites > 2 pixels
		imageCalculator("Subtract", "count","NaN");
		run("Analyze Particles...", "size=2-Infinity pixel show=Masks");
		run("Grays");
		run("Divide...", "value=255");
		saveAs("Tiff", dir+"sMASK/"+substring(t,0,lengthOf(t)-4)+"_mask.tif");
		close(); close("count"); close("NaN");
	}
}

selectWindow("Log");
saveAs("Text",dir+"sLOG/"+substring(t,0,lengthOf(t)-4)+"_lengths.txt");
run("Close");
roiManager("Reset");

//--- ASSEMBLE stacks and get PROFILES
setBatchMode(true);
make_stack("_str");
wait(1000);
close("*");
make_stack("mask");
wait(1000);
close("*");
setBatchMode(false);
waitForUser("Stacks sSTR_ and sMASK_ assembled!");


function set_IO(p){
	if (File.exists(p)){
		l=getFileList(p);
		if (l.length>0) for (j=0; j<l.length; j++) File.delete(p+File.separator+l[j]);
	}else{File.makeDirectory(p);}
}


function make_stack(r){
	newImage("stack", "8-bit black",sWidth, sHeight, 1);
	run("Set Measurements...", "mean redirect=None decimal=3");

	if (r=="mask") temp=dir+"sMASK/";
	if (r=="_str") temp=dir+"sSTR/";
	list = getFileList(temp);

	for (i=0; i<list.length; i++){
	    ext=substring(list[i],lengthOf(list[i])-8,lengthOf(list[i])-4);
	    if ((ext==r)){ //Open original images only
	    	open(temp+list[i]);
	    	h=getHeight();
	    	if (h>sWidth){//If axonal length longer than threshold...
		    	if (r=="_str"){
			    	//convert in 8-bit images
			    	setMinAndMax(0,max_intens);
			    	setOption("ScaleConversions", true);
					run("8-bit");
		    	}
		    	
				//Copy each image in a stakc and...
		    	run("Select All");
		    	run("Copy");
		    	close();
		    	selectWindow("stack");
		    	run("Add Slice");
		    	makeRectangle(0,0,sWidth, h);
		    	run("Paste");
	    	}
	    }
	} 
	setSlice(1);
	run("Select All");
	run("Delete Slice");
	//... save assembled stacks
	if (r=="mask") saveAs("Tiff",dir+"sMASK/sMASK_");
	if (r=="_str") saveAs("Tiff",dir+"sSTR/sSTR_");
	rename("stack");
	
	//Get profiles from saved stacks
	get_profiles(r);
}


function get_profiles(r){
	//Remove central axonal shaft ~ 20% original Width
	setForegroundColor(0,0,0);
	makeRectangle(0.4*sWidth,0,0.2*sWidth, sHeight);
	run("Fill", "stack");

	if (r=="mask") temp=dir+"sLOG/sMASK_";
	if (r=="_str") temp=dir+"sLOG/sSTR_";
	
	//For each slice, measure and write horizontal profile
	fileH=File.open(temp+"trans.txt");
	for (s=1; s<=nSlices;s++){
		selectWindow("stack");
		setSlice(s);
		line="";
		makeLine(0, sHeight/2, sWidth-1, sHeight/2, sHeight);
		trans=getProfile();	
		//The correction below is necessary to take into account the real length of each axon's
		for (f=0;f<trans.length;f++) line=line+(trans[f]*sHeight/length[s-1])+"\t";
		print(fileH, line+"\n");
	}
	File.close(fileH);
		
	//For each slice, measure and write vertical profile
	fileV=File.open(temp+"long.txt");
	for (s=1; s<=nSlices;s++){
		selectWindow("stack");
		setSlice(s);
		line="";
		makeLine(sWidth/2, 0, sWidth/2, sHeight-1, sWidth);
		long=getProfile();
		for (f=0;f<long.length;f++) line=line+long[f]+"\t";
		print(fileV, line+"\n");
	}
	File.close(fileV);
}
