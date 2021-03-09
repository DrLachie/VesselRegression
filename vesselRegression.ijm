
#@ File (label="Choose source directory", style="directory") dir1
#@ int (label="Select PECAM1 Channel", style="spinner", min=1, max=5, default=1) PecamChannel
#@ int (label="Select Whole Vascular Marker Channel", style="spinner", min=1, max=5, default=2) CollagenIV_Channel


/* 
 *  VesselCompare
 *  Find single stained vessel areas and compare lengths
 *  
 *  Written for Leigh Coultas, Emma Watson and Zoe Grant
 *  Code by Lachlan Whitehead (whitehead@wehi.edu.au)
 *  Feb 2015
 *  Feb 2020 - updated to use Morpholib-J plugins rather than depricated Fast_Morphology plugin
 *  
 */


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////

var PecamChannel = "C"+PecamChannel; //"C1" or "C2"
var CollagenIV_Channel = "C"+CollagenIV_Channel;
var fs = File.separator();
var dir1 = dir1 + fs;
var is16Bit = false;
var increaseSizeOfMaskForVisibility = 0; //set to zero for single pixel lines, >0 for thicker lines

checkForMorphologyPlugin();

run("Set Measurements...", "area limit redirect=None decimal=3");
run("Options...", "iterations=1 count=1 black");
run("Close All");


list = getFileList(dir1);
dir2 = dir1+"output"+fs;
if(!File.exists(dir2)){
	File.makeDirectory(dir2);
}



//Setup custom results table 
Table_Heading = "PECAM1 Length Measures";
columns = newArray("Filename","Total collagen IV length (um)", "Total PECAM1 length (um)", "PECAM1:Collagen ratio");
table = generateTable(Table_Heading,columns);

for(i=0;i<list.length;i++){	
	if(endsWith(list[i],".tif")){
		open(dir1+list[i]);
		run("Select None");
		
		getPixelSize(unit, pixelWidth, pixelHeight);
		fname = getTitle();
		if(bitDepth()==16){
			is16Bit = true;			
		}

		//A = 
		C1 = CollagenIV_Channel;
		run("Split Channels");
		selectWindow(C1+"-"+fname);
		rename("Keep me please");
		run("Duplicate...", "title=Prefiltered-mask");
		run("Median...","radius=2");

		//Threshold
		run("Threshold...");
		waitForUser("Adjust threshold");
		run("Convert to Mask");

		//Clean up Mask
		run("Morphological Filters", "operation=Opening element=Disk radius=6");
		run("Morphological Reconstruction", "marker=Prefiltered-mask-Opening mask=Prefiltered-mask type=[By Dilation] connectivity=4");
		run("Morphological Filters", "operation=Closing element=Disk radius=3");
		rename("Mask");

				
		close("Prefiltered*");

		//B = 
		selectWindow(PecamChannel+"-"+fname);
		run("Duplicate...", "title=Prefiltered-mask");
		run("Median...","radius=2");

		//Threshold
		run("Threshold...");
		setAutoThreshold("Triangle dark");
		waitForUser("Adjust threshold (again)");
		getThreshold(a,b);
		print(fname+" ("+a+","+b+")");
		run("Convert to Mask");

		//Clean up mask
		run("Morphological Filters", "operation=Closing element=Disk radius=12");
		run("Morphological Reconstruction", "marker=Prefiltered-mask-Closing mask=Prefiltered-mask type=[By Erosion] connectivity=4");
		run("Morphological Filters", "operation=Closing element=Disk radius=3");
		rename("Prefiltered-mask2");
		run("Morphological Filters", "operation=Opening element=Disk radius=5");
		run("Morphological Reconstruction", "marker=Prefiltered-mask2-Opening mask=Prefiltered-mask2 type=[By Dilation] connectivity=4");
		run("Morphological Filters", "operation=Dilation element=Disk radius=3");
		rename("Green Mask");
		
		close("Prefiltered*");

		//C = (B not A)
		imageCalculator("AND create", "Mask","Green Mask");
		selectWindow("Result of Mask");
		run("Invert");
		imageCalculator("AND create", "Result of Mask","Mask");
		rename("RedSansGreen");
		

		//Measure lengths of Vessels only in C
		run("Skeletonize (2D/3D)");
		selectWindow("Mask");
		run("Skeletonize (2D/3D)");
		
		imageCalculator("AND create", "Mask","RedSansGreen");
		rename("bits of interest");

		//filter out small bits (<5 pixels);
		run("Analyze Particles...", "size=5-Infinity pixel clear add");
		selectArray = newArray(roiManager("Count"));
		for(a=0;a<selectArray.length;a++){
			selectArray[a] = a;
		}	
		
		roiManager("Select",selectArray);
		setBackgroundColor(0,0,0);
		roiManager("Combine");
		roiManager("Add");
		roiCount = roiManager("Count");
		roiManager("Select",roiCount-1);
		run("Clear Outside");

				
		run("Set Measurements...", "area limit redirect=None decimal=3");
		setThreshold(1,255);
		run("Measure");
		area = getResult("Area",nResults()-1);
		regions_length = area / pixelWidth;
		
		//Measure length of all vesssels in A	
		selectWindow("Mask");
		setThreshold(1,255);
		run("Measure");
		area = getResult("Area",nResults()-1);
		total_length = area / pixelWidth;
		
		selectWindow("bits of interest");
		if (increaseSizeOfMaskForVisibility!=0){
			run("Select None");
			run("Maximum...", "radius="+increaseSizeOfMaskForVisibility);
		}
		
		if(is16Bit){
			run("16-bit");
		}


		
		//Create composite image for review
		selectWindow("Keep me please");
		
		run("Merge Channels...", "c1=[Keep me please] c2=["+PecamChannel+"-"+fname+"] c3=[*None*] c4=[*None*] c7=[bits of interest] create ignore keep");

		Stack.setChannel(1);run("Green");resetMinAndMax();run("Enhance Contrast", "saturated=0.2");
		Stack.setChannel(2);run("Magenta");resetMinAndMax();run("Enhance Contrast", "saturated=0.2");
		Stack.setChannel(3);run("Yellow");resetMinAndMax();
		
		run("RGB Color");
		roiManager("Show All without Labels");
		run("Flatten");
		
		saveAs("JPEG",dir2+substring(fname,0,lengthOf(fname)-4)+"_mask.jpg");


		//log results
		resultArray = newArray(fname,total_length,regions_length,1 - (regions_length/total_length));
		logResults(table,resultArray);
		run("Close All");
		
	}
}



	


//Generate a custom table
//Give it a title and an array of headings
//Returns the name required by the logResults function
function generateTable(tableName,column_headings){
	if(isOpen(tableName)){
		selectWindow(tableName);
		run("Close");
	}
	tableTitle=tableName;
	tableTitle2="["+tableTitle+"]";
	run("Table...","name="+tableTitle2+" width=600 height=250");
	newstring = "\\Headings:"+column_headings[0];
	for(i=1;i<column_headings.length;i++){
			newstring = newstring +" \t " + column_headings[i];
	}
	print(tableTitle2,newstring);
	return tableTitle2;
}


//Log the results into the custom table
//Takes the output table name from the generateTable funciton and an array of resuts
//No checking is done to make sure the right number of columns etc. Do that yourself
function logResults(tablename,results_array){
	resultString = results_array[0]; //First column
	//Build the rest of the columns
	for(i=1;i<results_array.length;i++){
		resultString = toString(resultString + " \t " + results_array[i]);
	}
	//Populate table
	print(tablename,resultString);
}




function checkForMorphologyPlugin(){
	pluginDir = getDirectory("plugins");
	if(!File.exists(pluginDir+File.separator()+"MorphoLibJ_-1.4.2.1.jar")){
		showMessage("Morpholib-J plugin required. \n\nPlease activate the IJPM-plugins update site and restart FIJI.");		
		exit();
	}
}

