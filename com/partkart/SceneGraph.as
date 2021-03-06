﻿package com.partkart{

	import flash.display.*;
	import flash.ui.Keyboard;
	import flash.events.*;
	import flash.text.*;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.utils.Timer;
	import fl.controls.ComboBox;
	import flash.ui.Mouse;
	import flash.net.FileReference;
	import fl.data.DataProvider;
	import flash.filters.BlurFilter;
	import flash.filters.ColorMatrixFilter;
	import flash.geom.Matrix;
	import flash.ui.MouseCursor;

	import com.tink.display.HitTest;

	// the scene graph is a root node containing all rendered objects
	public class SceneGraph extends Sprite{

		public var pathlist:Array = new Array(); // list of all paths
		public var copylist:Array = new Array(); // copy/paste buffer

		public var cutlist:Array = new Array(); // list of all cutobjects

		public var xstart:Number = 0;
		public var ystart:Number = 0;

		public var ctrl:Boolean = false;

		private static var singleton:SceneGraph; // only one instance of the scene graph ias allowed

		private var progressdialog:ProgressDialog;

		public var nestpath:Path = null;
		private var nest:Nest = null;

		// list of cutobjects that is waiting to be processed (use for progress bar udpates)
		public var processlist:Array;

		public function SceneGraph(caller: Function = null):void{
			if(caller != SceneGraph.getInstance){
				throw new Error ("SceneGraph is a singleton class, use getInstance() instead");
			}
			if (SceneGraph.singleton != null){
				throw new Error( "Only one Singleton instance should be instantiated");
			}
			this.cacheAsBitmap = true;
		}

		public static function getInstance():SceneGraph{
			if (singleton == null){
				singleton = new SceneGraph(arguments.callee);
			}
			return singleton;
		}

		public function addPath(p:Path):void{
			addChild(p);
			p.render();
			pathlist.push(p);
			p.addEventListener(MouseEvent.MOUSE_DOWN, pathMouseDown);
		}

		public function removePath(p:Path):Boolean{
			if(p && contains(p)){
				removeChild(p);
			}
			var index:int = pathlist.indexOf(p);
			if(index == -1){
				return false;
			}
			pathlist.splice(index,1);
			return true;
		}

		public function addPaths(list:Array):void{
			for(var i:int=0; i<list.length; i++){
				addChild(list[i]);
				pathlist.push(list[i]);
				list[i].addEventListener(MouseEvent.MOUSE_DOWN, pathMouseDown);
			}
			//redraw();
			for(i=0; i<list.length; i++){
				list[i].setActive();
			}
		}

		public function setInactive():void{
			for(var i:int=0; i<pathlist.length; i++){
				pathlist[i].setInactive();
			}

			for(i=0; i<cutlist.length; i++){
				cutlist[i].setInactive();
			}
		}

		public function getActiveCuts():Array{
			var active:Array = new Array();
			for(var i:int=0; i<cutlist.length; i++){
				if(cutlist[i].active == true){
					active.push(cutlist[i]);
				}
			}
			return active;
		}

		// removes dots and coordinate boxes from the screen, if p is defined, exclude p from clearing
		public function clearDots(p:Path = null):void{
			for(var i:int = 0; i<pathlist.length; i++){
				if(p == null || (p != null && pathlist[i] != p)){
					pathlist[i].setSegmentsInactive();
					pathlist[i].setDotsInactive();
					pathlist[i].clearDots();
				}
			}

			var removelist:Array = new Array();

			for(i = 0; i<numChildren; i++){
				if((getChildAt(i) is coordinates) && (p == null || (p != null && p.coord != getChildAt(i)))){
					removelist.push(getChildAt(i));
				}
			}

			for(i=0;i<removelist.length; i++){
				removeChild(removelist[i]);
			}
		}

		public function addDots():void{
			for each(var path:Path in pathlist){
				path.redrawDots();
			}
		}

		public function redraw():void{
			trace("redraw!");

			// no redrawing during calculations
			if(Global.tool != 99){
				clearDots();
				x = Global.xorigin;
				y = Global.yorigin;

				while(numChildren > 0){
					removeChildAt(0);
				}

				// stack cutobjects at the bottom
				for each(var cut:CutObject in cutlist){
					addChild(cut);
				}

				// paths on top
				for each(var path in pathlist){
					addChild(path);

					path.x = path.docx*Global.zoom;
					path.y = path.docy*Global.zoom;

					path.redraw();
				}

				redrawCuts();
			}
		}

		public function redrawCuts():void{
			for each(var cutobject:CutObject in cutlist){
				cutobject.x = cutobject.docx*Global.zoom;
				cutobject.y = cutobject.docy*Global.zoom;

				cutobject.redraw();
			}
			for each(cutobject in cutlist){
				if(cutobject.processed == false){
					for each(var path:Path in cutobject.pathlist){
						path.dirty = false;
					}
				}
			}
		}

		public function cmToInch():void{
			for(var i:int=0; i<pathlist.length; i++){
				pathlist[i].cmToInch();
				pathlist[i].dirty = true;
			}
			for(i=0; i<cutlist.length; i++){
				if(cutlist[i].processed == true){
					cutlist[i].cmToInch();
				}
				else{
					cutlist[i].paramsCmToInch();
				}
			}

			Global.tolerance /= 2.54;
		}

		public function inchToCm():void{
			for(var i:int=0; i<pathlist.length; i++){
				pathlist[i].inchToCm();
				pathlist[i].dirty = true;
			}
			for(i=0; i<cutlist.length; i++){
				if(cutlist[i].processed == true){
					cutlist[i].inchToCm();
				}
				else{
					cutlist[i].paramsInchToCm();
				}
			}

			Global.tolerance *= 2.54;
		}

		public function pathMouseDown(e:MouseEvent):void{

			stage.focus = null;

			if(Global.tool == 3 && Global.space == false){
				e.stopPropagation();
			}
			else if(Global.tool == 0 && Global.space == false){
				e.stopPropagation();

				var path:Path;

				if(e.target is Segment){
					path = e.target.parent as Path;
				}
				else if(e.target is Path){
					path = e.target as Path;
				}

				if(path != null){
					path.startDrag();
					path.dragging = true;
					path.mouseChildren = false;

					xstart = e.stageX;
					ystart = e.stageY;

					addChild(path); // put path on top of z-stack

					if(ctrl == true){
						if(path.active){
							path.setInactive();
						}
						else{
							path.setActive();
						}
					}
					else if(path.active == false || getPathNumActive() < 2){
						clearDots();
						setInactive();
						path.setActive();
					}

					for(var i:int = 0; i<pathlist.length; i++){
						if(pathlist[i].active && pathlist[i] != path){
							path.addChild(pathlist[i]);

							pathlist[i].x -= path.x;
							pathlist[i].y -= path.y;
						}
					}

					for(i=0; i<cutlist.length; i++){
						var parents:Array = cutlist[i].pathlist;
						var movecut:Boolean = true;
						for each(var p:Path in parents){
							if(p.active == false){
								movecut = false;
							}
						}
						if(movecut == true){
							path.addChild(cutlist[i]);

							cutlist[i].x -= path.x;
							cutlist[i].y -= path.y;
						}
					}

					path.addEventListener(MouseEvent.MOUSE_UP, pathMouseUp);
				}
			}
		}

		public function pathMouseUp(e:MouseEvent, epath:Path = null):void{
			var path:Path;

			if(epath != null){
				path = epath;
			}
			else if(e.target is Segment){
				path = e.target.parent as Path;
			}
			else if(e.target is Path){
				path = e.target as Path;
			}
			if(path != null){

				while(path.parent is Path){
					path = path.parent as Path;
				}

				path.stopDrag();
				path.dragging = false;
				path.mouseChildren = true;

				trace("uppped");
				if(path != null && Global.tool == 0){ // don't do this stuff during sketching
					var xdelta:Number = e.stageX - xstart;
					var ydelta:Number = e.stageY - ystart;

					if(isNaN(xdelta)){
						xdelta = 0;
					}

					if(isNaN(ydelta)){
						ydelta = 0;
					}

					path.docx += xdelta/Global.zoom;
					path.docy += ydelta/Global.zoom;

					path.x = path.docx*Global.zoom;
					path.y = path.docy*Global.zoom;

					var plist:Array = new Array();

					if(path){
						var p:*;
						for(var i=0; i<path.numChildren; i++){
							p = path.getChildAt(i);
							if(p is Path || p is CutObject){
								plist.push(path.getChildAt(i));
							}
						}

						for each(p in plist){
							p.docx += xdelta/Global.zoom;
							p.docy += ydelta/Global.zoom;

							p.x = p.docx*Global.zoom;
							p.y = p.docy*Global.zoom;
							this.addChild(p);
						}
					}

					if(xdelta != 0 || ydelta != 0){
						// setup undo
						var undo:UndoMove = new UndoMove(this);
						undo.xdelta = xdelta/Global.zoom;
						undo.ydelta = ydelta/Global.zoom;
						undo.pathlist = plist;
						undo.pathlist.push(path);

						Global.undoPush(undo);

						// if the paths of a cutobject are all moved at once, they are not dirty. Otherwise the path is dirty
						/*var clist:Array = new Array();
						for each(p in plist){
							if(p is CutObject){
								clist.push(p);
							}
						}*/
						for each(var c:CutObject in cutlist){
							var moved:int = 0;
							for each(path in c.pathlist){
								if(plist.indexOf(path) != -1){
									moved++;
								}
							}
							if(moved > 0 && moved < c.pathlist.length){
								for each(path in c.pathlist){
									if(plist.indexOf(path) != -1){
										path.dirty = true;
										path.camdirty = true;
									}
								}
							}
						}
					}
				}

				// paths on top
				for(i=0; i<pathlist.length; i++){
					addChild(pathlist[i]);
				}

				path.removeEventListener(MouseEvent.MOUSE_UP, pathMouseUp);
			}

			redrawCuts();
		}

		// fires mouseup events when mouse leaves stage
		public function mouseLeave():void{
			for(var i:int = 0; i<pathlist.length; i++){
				if(pathlist[i].dragging == true){
					pathMouseUp(new MouseEvent(MouseEvent.MOUSE_UP), pathlist[i]);
				}
				pathlist[i].pubPointUpAction();
			}
		}

		public function select(selectbox:Sprite):void{
			// set selected paths to active

			var perfect:Boolean = true;

			if(pathlist.length > 1000){ // when you're selecting more than 1000 elements, you're probably not going for accuracy
				perfect = false;
			}

			selectbox.alpha = 1;

			for(var i:int=0; i<pathlist.length; i++){
				if(HitTest.complexHitTestObject(selectbox, pathlist[i])){
					if(pathlist[i].active){
						pathlist[i].setInactive();
					}
					else{
						pathlist[i].setActive();
					}
				}
			}

			for(i=0; i<cutlist.length; i++){
				if(HitTest.complexHitTestObject(selectbox, cutlist[i])){
					if(cutlist[i].active){
						cutlist[i].setInactive();
					}
					else{
						cutlist[i].setActive();
					}
				}
			}
		}

		public function deleteSelected():void{

			// keep track of removed cuts/paths
			var removedcuts:Array = new Array();
			var removedpaths:Array = new Array();
			// keeps track of parent relationships between cuts and paths
			var cutparent:Array = new Array();

			var i:int;

			// remove selected paths from cutlist
			for(i=0; i<cutlist.length; i++){
				for(var j:int=0; j<pathlist.length; j++){
					var dirty:Boolean = false;

					if(pathlist[j].active == true){
						cutparent.push({cut:cutlist[i], path:pathlist[j]});
						var index:int = cutlist[i].pathlist.indexOf(pathlist[j]);
						if(index != -1){
							cutlist[i].pathlist.splice(index,1);
							dirty = true;
						}
					}
					// delete the cutobject if it has no paths left
					if(cutlist[i].pathlist.length == 0){
						var cut:CutObject = cutlist[i];
						if(removeCut(cut)){
							removedcuts.push(cut);
							i--;
							break;
						}
					}
					else if(dirty){
						cutlist[i].pathlist[0].dirty = true;
						cutlist[i].pathlist[0].camdirty = true;
					}
				}
			}

			i=0;

			var path:Path;

			// remove selected paths from pathlist, remove selected segments
			while(i<pathlist.length){
				path = pathlist[i];

				if(path.active == true){
					removedpaths.push(path);
					if(removePath(path)){
						i--;
					}
				}
				else{
					if(path.deleteActive() == true){
						if(removePath(path)){
							i--;
						}
					}
				}
				i++;
			}

			for(i=0; i<cutlist.length; i++){
				cut = cutlist[i];
				if(cutlist[i].active == true){
					if(removeCut(cut)){
						removedcuts.push(cut);
						i--;
					}
				}
			}

			if(removedpaths.length > 0 || removedcuts.length > 0){
				// set up undo
				var undo:UndoDelete = new UndoDelete(this);
				undo.pathlist = removedpaths;
				undo.cutlist = removedcuts;
				undo.cutparent = cutparent;

				Global.undoPush(undo);
			}

			// remove tabs
			for(i=0; i<cutlist.length; i++){
				cutlist[i].removeActiveTabs();
			}

			clearDots();
		}

		public function getPathNumActive():int{
			var n:int = 0;
			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					n++;
				}
			}

			return n;
		}

		public function startCopy():void{

			copylist = new Array();

			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					var p:Path = pathlist[i].clone();
					//p.redrawDots();
					copylist.push(p);
				}
			}
		}

		public function startPaste(p:Point = null):void{

			// if given a point, align pasted paths to that point

			setInactive();

			if(p != null && copylist.length > 0){
				var min:Point = copylist[0].getMin().clone();
				for(var j:int=0; j<copylist.length; j++){
					var m:Point = copylist[j].getMin();
					if(m.x < min.x){
						min.x = m.x;
					}
					if(m.y < min.y){
						min.y = m.y;
					}
				}

				var diff:Point = new Point(p.x-min.x, p.y-min.y);

				for(j=0; j<copylist.length; j++){
					copylist[j].docx += diff.x;
					copylist[j].docy -= diff.y;

					copylist[j].x = copylist[j].docx*Global.zoom + Global.xorigin;
					copylist[j].y = -copylist[j].docy*Global.zoom + Global.yorigin;
				}
			}

			addPaths(copylist);
			redraw();

			var newlist:Array = new Array();
			for(var i:int=0; i<copylist.length; i++){
				newlist.push(copylist[i].clone());
			}

			copylist = newlist;
		}

		// applies the given matrix as a local transform on selected paths
		public function applyMatrixLocal(m:Matrix):void{
			// applies the given matrix transform to all active paths

			// now we normalize the result so that the middle point of the previous and current spaces are identical

			var average:Point = new Point(0,0);
			var len:int = 0;

			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					var pathav:Point = pathlist[i].getAverage();
					average.x += pathav.x;
					average.y += pathav.y;

					len++;
				}
			}

			average.x = average.x/len;
			average.y = average.y/len;

			var newaverage:Point = m.transformPoint(average);

			var dis:Point = new Point(newaverage.x-average.x, newaverage.y-average.y);

			// apply the matrix now
			for(i=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					pathlist[i].matrixTransform(m);
					var newdoc:Point = m.transformPoint(new Point(pathlist[i].docx, -pathlist[i].docy));
					pathlist[i].docx = newdoc.x;
					pathlist[i].docy = -newdoc.y;
				}
			}

			// normalize
			for(i=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					pathlist[i].docx -= dis.x;
					pathlist[i].docy += dis.y;
				}
			}

			redraw();
		}

		public function closeLoop(dot:Dot):Point{

			var snappoint:Point;
			for(var i:int=0; i<pathlist.length; i++){
				snappoint = pathlist[i].snapPoint(dot);
				if(snappoint != null){
					if(dot){
						dot.looppath = pathlist[i];
					}
					return snappoint;
				}
			}

			return null;
		}

		// CAM operations start here

		public function profile(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var outside:Boolean = flist[3].input.selectedItem.data;
			var safetyheight:Number = Number(flist[4].input.text);
			var stocksurface:Number = Number(flist[5].input.text);
			var stepdown:Number = Math.abs(Number(flist[6].input.text));
			var feedrate:Number = Math.abs(Number(flist[7].input.text));
			var plungerate:Number = Math.abs(Number(flist[8].input.text));
			var dir:int = flist[9].input.selectedItem.data;

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
			}

			if(isNaN(safetyheight) || isNaN(stocksurface) || isNaN(targetdepth) || isNaN(tooldiameter) || tooldiameter == 0 || isNaN(stepdown) || stepdown == 0 || isNaN(feedrate) || feedrate == 0 || isNaN(plungerate) || plungerate == 0){
				return;
			}

			var selectedpaths:Array = new Array();
			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					selectedpaths.push(pathlist[i]);
				}
			}

			var cut:ProfileCutObject = new ProfileCutObject();

			cut.name = cutname;
			cut.outside = outside;
			cut.safetyheight = safetyheight;
			cut.stocksurface = stocksurface;
			cut.targetdepth = targetdepth;
			cut.tooldiameter = tooldiameter;
			cut.stepdown = stepdown;
			cut.feedrate = feedrate;
			cut.plungerate = plungerate;
			cut.dir = dir;

			cut.pathlist = selectedpaths;

			addCut(cut);

			//var result:Array = cut.process(selectedpaths);

			/*if(result == null || result.length == 0){
				removeChild(cut);
				cutlist.splice(cutlist.indexOf(cut),1);
			}*/

			redraw();
		}

		public function editprofile(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var outside:Boolean = flist[3].input.selectedItem.data;
			var safetyheight:Number = Number(flist[4].input.text);
			var stocksurface:Number = Number(flist[5].input.text);
			var stepdown:Number = Math.abs(Number(flist[6].input.text));
			var feedrate:Number = Math.abs(Number(flist[7].input.text));
			var plungerate:Number = Math.abs(Number(flist[8].input.text));
			var dir:int = flist[9].input.selectedItem.data;

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
			}

			var main:* = this.parent;

			var cut:ProfileCutObject = main.tools.dToolpaths.selectedItem.data;

			var redrawcut:Boolean = false;
			if(cut.tooldiameter != tooldiameter || cut.outside != outside || cut.dir != dir){
				redrawcut = true;
			}

			cut.name = cutname;
			main.tools.dToolpaths.selectedItem.label = cutname;
			cut.outside = outside;
			cut.safetyheight = isNaN(safetyheight) ? cut.safetyheight : safetyheight;
			cut.stocksurface = isNaN(stocksurface) ? cut.stocksurface : stocksurface;
			cut.targetdepth = isNaN(targetdepth) ? cut.targetdepth : targetdepth;
			cut.tooldiameter = (isNaN(tooldiameter) || tooldiameter == 0) ? cut.tooldiameter : tooldiameter;
			cut.stepdown = (isNaN(stepdown) || stepdown == 0) ? cut.stepdown : stepdown;
			cut.feedrate = (isNaN(feedrate) || feedrate == 0) ? cut.feedrate : feedrate;
			cut.plungerate = (isNaN(plungerate) || plungerate == 0) ? cut.plungerate : plungerate;
			cut.dir = dir;

			if(redrawcut){
				cut.pathlist[0].dirty = true;
				cut.pathlist[0].camdirty = true;
				cut.processed = false;
				redraw();
			}
		}

		public function pocket(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var safetyheight:Number = Number(flist[3].input.text);
			var stocksurface:Number = Number(flist[4].input.text);
			var stepover:Number = 0.01*Math.abs(Number(flist[5].input.text));
			var stepdown:Number = Math.abs(Number(flist[6].input.text));
			var roughingclearance:Number = Math.abs(Number(flist[7].input.text));
			var feedrate:Number = Math.abs(Number(flist[8].input.text));
			var plungerate:Number = Math.abs(Number(flist[9].input.text));
			var dir:int = flist[10].input.selectedItem.data;

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
				roughingclearance /= 10;
			}

			if(isNaN(safetyheight) || isNaN(stocksurface) || isNaN(targetdepth) || isNaN(tooldiameter) || isNaN(stepdown) || stepdown == 0 || isNaN(stepover) || stepover == 0 || isNaN(feedrate) || feedrate == 0 || isNaN(plungerate) || plungerate == 0 || isNaN(roughingclearance)){
				return;
			}

			var selectedpaths:Array = new Array();
			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					selectedpaths.push(pathlist[i]);
				}
			}

			var cut:PocketCutObject = new PocketCutObject();

			cut.name = cutname;
			cut.safetyheight = safetyheight;
			cut.stocksurface = stocksurface;
			cut.targetdepth = targetdepth;
			cut.tooldiameter = tooldiameter;
			cut.stepover = stepover;
			cut.stepdown = stepdown;
			cut.roughingclearance = roughingclearance;
			cut.feedrate = feedrate;
			cut.plungerate = plungerate;
			cut.dir = dir;

			cut.pathlist = selectedpaths;

			addCut(cut);

			//var result:Array = cut.process(selectedpaths);

			/*if(result == null || result.length == 0){
				removeChild(cut);
				cutlist.splice(cutlist.indexOf(cut),1);
			}*/

			redraw();
		}

		public function editpocket(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var safetyheight:Number = Number(flist[3].input.text);
			var stocksurface:Number = Number(flist[4].input.text);
			var stepover:Number = 0.01*Math.abs(Number(flist[5].input.text));
			var stepdown:Number = Math.abs(Number(flist[6].input.text));
			var roughingclearance:Number = Math.abs(Number(flist[7].input.text));
			var feedrate:Number = Math.abs(Number(flist[8].input.text));
			var plungerate:Number = Math.abs(Number(flist[9].input.text));
			var dir:int = flist[10].input.selectedItem.data;

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
				roughingclearance /= 10;
			}

			var main:* = this.parent;
			var cut:PocketCutObject = main.tools.dToolpaths.selectedItem.data;

			var redrawcut:Boolean = false;
			if(tooldiameter != cut.tooldiameter || roughingclearance != cut.roughingclearance || stepover != cut.stepover || dir != cut.dir){
				redrawcut = true;
			}

			cut.name = cutname;
			main.tools.dToolpaths.selectedItem.label = cutname;
			cut.safetyheight = isNaN(safetyheight) ? cut.safetyheight : safetyheight;
			cut.stocksurface = isNaN(stocksurface) ? cut.stocksurface : stocksurface;
			cut.targetdepth = isNaN(targetdepth) ? cut.targetdepth : targetdepth;
			cut.tooldiameter = (isNaN(tooldiameter) || tooldiameter == 0) ? cut.tooldiameter : tooldiameter;
			cut.stepover = (isNaN(stepover) || stepover == 0) ? cut.stepover : stepover;
			cut.stepdown = (isNaN(stepdown) || stepdown == 0) ? cut.stepdown : stepdown;
			cut.roughingclearance = isNaN(roughingclearance) ? cut.roughingclearance : roughingclearance;
			cut.feedrate = (isNaN(feedrate) || feedrate == 0) ? cut.feedrate : feedrate;
			cut.plungerate = (isNaN(plungerate) || plungerate == 0) ? cut.plungerate : plungerate;
			cut.dir = dir;

			if(redrawcut){
				cut.pathlist[0].dirty = true;
				cut.pathlist[0].camdirty = true;
				cut.processed = false;
				redraw();
			}
		}

		public function followpath(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var safetyheight:Number = Number(flist[3].input.text);
			var stocksurface:Number = Number(flist[4].input.text);
			var stepdown:Number = Math.abs(Number(flist[5].input.text));
			var feedrate:Number = Math.abs(Number(flist[6].input.text));
			var plungerate:Number = Math.abs(Number(flist[7].input.text));

			if(isNaN(tooldiameter) || isNaN(safetyheight) || isNaN(stocksurface) || isNaN(targetdepth) || isNaN(stepdown) || stepdown == 0 || isNaN(feedrate) || feedrate == 0 || isNaN(plungerate) || plungerate == 0){
				return;
			}

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
			}

			var selectedpaths:Array = new Array();
			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					selectedpaths.push(pathlist[i]);
				}
			}

			var cut:FollowPathCutObject = new FollowPathCutObject();

			cut.name = cutname;
			cut.tooldiameter = tooldiameter;
			cut.targetdepth = targetdepth;
			cut.safetyheight = safetyheight;
			cut.stocksurface = stocksurface;
			cut.stepdown = stepdown;
			cut.feedrate = feedrate;
			cut.plungerate = plungerate;

			cut.pathlist = selectedpaths;

			addCut(cut);

			/*var result:Array = cut.process(selectedpaths);

			if(result == null || result.length == 0){
				removeChild(cut);
				cutlist.splice(cutlist.indexOf(cut),1);
			}*/

			redraw();
		}

		public function editfollowpath(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var safetyheight:Number = Number(flist[3].input.text);
			var stocksurface:Number = Number(flist[4].input.text);
			var stepdown:Number = Math.abs(Number(flist[5].input.text));
			var feedrate:Number = Math.abs(Number(flist[6].input.text));
			var plungerate:Number = Math.abs(Number(flist[7].input.text));

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
			}

			var main:* = this.parent;
			var cut:FollowPathCutObject = main.tools.dToolpaths.selectedItem.data;

			cut.name = cutname;
			main.tools.dToolpaths.selectedItem.label = cutname;
			cut.tooldiameter = (isNaN(tooldiameter) || tooldiameter == 0) ? cut.tooldiameter : tooldiameter;
			cut.safetyheight = isNaN(safetyheight) ? cut.safetyheight : safetyheight;
			cut.stocksurface = isNaN(stocksurface) ? cut.stocksurface : stocksurface;
			cut.targetdepth = isNaN(targetdepth) ? cut.targetdepth : targetdepth;
			cut.stepdown = (isNaN(stepdown) || stepdown == 0) ? cut.stepdown : stepdown;
			cut.feedrate = (isNaN(feedrate) || feedrate == 0) ? cut.feedrate : feedrate;
			cut.plungerate = (isNaN(plungerate) || plungerate == 0) ? cut.plungerate : plungerate;

			redraw();
		}

		public function drill(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var center:Boolean = flist[3].input.selectedItem.data;
			var spacing:Number = Number(flist[4].input.text);
			var safetyheight:Number = Number(flist[5].input.text);
			var stocksurface:Number = Number(flist[6].input.text);
			var stepdown:Number = Math.abs(Number(flist[7].input.text));
			var plungerate:Number = Math.abs(Number(flist[8].input.text));

			if(isNaN(tooldiameter) || isNaN(safetyheight) || isNaN(stocksurface) || isNaN(targetdepth) || isNaN(stepdown) || stepdown == 0 || isNaN(plungerate) || plungerate == 0 || isNaN(spacing) || spacing == 0){
				return;
			}

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
				spacing /= 10;
			}

			var selectedpaths:Array = new Array();
			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					selectedpaths.push(pathlist[i]);
				}
			}

			var cut:DrillCutObject = new DrillCutObject();

			cut.name = cutname;
			cut.tooldiameter = tooldiameter;
			cut.targetdepth = targetdepth;
			cut.center = center;
			cut.spacing = spacing;
			cut.safetyheight = safetyheight;
			cut.stocksurface = stocksurface;
			cut.stepdown = stepdown;
			cut.plungerate = plungerate;

			cut.pathlist = selectedpaths;

			addCut(cut);

			/*var result:Array = cut.process(selectedpaths);

			if(result == null || result.length == 0){
				removeChild(cut);
				cutlist.splice(cutlist.indexOf(cut),1);
			}*/

			redraw();
		}

		public function editdrill(flist:Array):void{

			// filter input
			var cutname:String = String(flist[0].input.text);
			var tooldiameter:Number = Math.abs(Number(flist[1].input.text));
			var targetdepth:Number = Number(flist[2].input.text);
			var center:Boolean = flist[3].input.selectedItem.data;
			var spacing:Number = Number(flist[4].input.text);
			var safetyheight:Number = Number(flist[5].input.text);
			var stocksurface:Number = Number(flist[6].input.text);
			var stepdown:Number = Math.abs(Number(flist[7].input.text));
			var plungerate:Number = Math.abs(Number(flist[8].input.text));

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
				spacing /= 10;
			}

			var main:* = this.parent;
			var cut:DrillCutObject = main.tools.dToolpaths.selectedItem.data;

			var redrawcut:Boolean = false;
			if(center != cut.center){
				redrawcut = true;
			}

			cut.name = cutname;
			main.tools.dToolpaths.selectedItem.label = cutname;
			cut.tooldiameter = (isNaN(tooldiameter) || tooldiameter == 0) ? cut.tooldiameter : tooldiameter;
			cut.center = center;
			cut.spacing = (isNaN(spacing) || spacing == 0) ? cut.spacing : spacing;
			cut.safetyheight = isNaN(safetyheight) ? cut.safetyheight : safetyheight;
			cut.stocksurface = isNaN(stocksurface) ? cut.stocksurface : stocksurface;
			cut.targetdepth = isNaN(targetdepth) ? cut.targetdepth : targetdepth;
			cut.stepdown = (isNaN(stepdown) || stepdown == 0) ? cut.stepdown : stepdown;
			cut.plungerate = (isNaN(plungerate) || plungerate == 0) ? cut.plungerate : plungerate;

			if(redrawcut){
				cut.pathlist[0].dirty = true;
				cut.pathlist[0].camdirty = true;
				cut.processed = false;
			}

			redraw();
		}

		public function batch(flist:Array):void{
			// filter input
			var tooldiameter:Number = Math.abs(Number(flist[0].input.text));
			var targetdepth:Number = Number(flist[1].input.text);
			var outside:Boolean = flist[2].input.selectedItem.data;
			var safetyheight:Number = Number(flist[3].input.text);
			var stocksurface:Number = Number(flist[4].input.text);
			var stepover:Number = 0.01*Math.abs(Number(flist[5].input.text));
			var stepdown:Number = Math.abs(Number(flist[6].input.text));
			var roughingclearance:Number = Math.abs(Number(flist[7].input.text));
			var feedrate:Number = Math.abs(Number(flist[8].input.text));
			var plungerate:Number = Math.abs(Number(flist[9].input.text));
			var dir:int = flist[10].input.selectedItem.data;
			var center:Boolean = flist[11].input.selectedItem.data;
			var spacing:Number = Number(flist[12].input.text);

			if(Global.unit == "cm"){
				// internal units are cm whereas machining units are given in mm
				tooldiameter /= 10;
				roughingclearance /= 10;
			}

			if(isNaN(safetyheight) || isNaN(stocksurface) || isNaN(targetdepth) || isNaN(tooldiameter) || isNaN(stepdown) || stepdown == 0 || isNaN(feedrate) || feedrate == 0 || isNaN(plungerate) || plungerate == 0){
				return;
			}

			var selectedcuts:Array = new Array();
			for(var i:int=0; i<cutlist.length; i++){
				if(cutlist[i].active == true){
					selectedcuts.push(cutlist[i]);
				}
			}

			for each(var cut:* in selectedcuts){
				cut.pathlist[0].dirty = true;
				cut.pathlist[0].camdirty = true;
				cut.processed = false;

				cut.safetyheight = safetyheight;
				cut.stocksurface = stocksurface;
				cut.outside = outside;
				cut.targetdepth = targetdepth;
				cut.tooldiameter = tooldiameter;
				cut.stepover = stepover;
				cut.stepdown = stepdown;
				cut.roughingclearance = roughingclearance;
				cut.feedrate = feedrate;
				cut.plungerate = plungerate;
				cut.dir = dir;

				cut.center = center;
				cut.spacing = spacing;
			}

			redraw();
		}

		public function zeroSelected():void{
			for(var i:int=0; i<pathlist.length; i++){
				if(pathlist[i].active == true){
					pathlist[i].zeroOrigin();
				}
			}
		}

		public function getProcessedCuts():Array{
			var processed:Array = new Array();
			for(var i:int=0; i<cutlist.length; i++){
				if(cutlist[i].processed == true){
					processed.push(cutlist[i]);
				}
			}

			return processed;
		}

		public function addCut(cut:CutObject):void{
			var cutgroup:Array = new Array(cut);

			if(Global.separatetoolpaths){
				cutgroup = cut.group();
			}

			for each(cut in cutgroup){
				cutlist.push(cut);
				addChild(cut);

				// all paths of the cutobject are dirty to start with
				for each(var path:Path in cut.pathlist){
					path.dirty = true;
					path.camdirty = true;
				}

				var main:* = this.parent;
				main.tools.dToolpaths.addItem({label: cut.name, data: cut});
				main.tools.dToolpaths.height = Math.max(cutlist.length*20,20);
				cut.setActive();
			}
		}

		public function removeCut(cut:CutObject):Boolean{
			if(cut == null){
				return false;
			}
			if(this.contains(cut)){
				removeChild(cut);
			}
			var index:int = cutlist.indexOf(cut);
			if(index != -1){
				cutlist.splice(index,1);
				var main:* = this.parent;
				main.tools.dToolpaths.removeItemAt(index);
				main.tools.dToolpaths.height = Math.max(cutlist.length*20,20);
				return true;
			}
			else{
				return false;
			}
		}

		public function reprocessCuts(pd:ProgressDialog, activeonly:Boolean = false, cut:CutObject=null):void{
			progressdialog = pd;
			processlist = new Array();

			if(cut != null){
				processlist.push(cut);
			}
			else{
				for each(var cut:CutObject in cutlist){
					if(activeonly && cut.active == false){
						continue;
					}
					var reprocess:Boolean = false;
					for each(var path:Path in cut.pathlist){
						path.zeroOrigin();
						path.redraw();
						if(path.camdirty == true){
							path.camdirty = false;
							reprocess = true;
						}
					}
					if(reprocess || cut.processed == false){
						processlist.push(cut);
					}
				}
			}

			progressdialog.init(processlist.length);

			processNext();

			redraw();
		}

		protected function processNext():void{
			if(processlist.length > 0){
				var cut:CutObject = processlist[0];
				cut.addEventListener(ProgressEvent.PROGRESS, cutProgress);
				cut.addEventListener(Event.COMPLETE, cutComplete);
				cut.start();
				//processlist.shift();
			}
			else{
				// cleanup
				progressdialog.stopDialog();
			}
		}

		protected function cutProgress(e:ProgressEvent):void{
			var cutprogress:Number = Math.min(e.bytesLoaded/e.bytesTotal,1);
			var totalprogress:Number = progressdialog.total - processlist.length + cutprogress;
			progressdialog.setProgress(totalprogress);
		}

		protected function cutComplete(e:Event){
			if(e.target is CutObject){
				var cut:CutObject = e.target as CutObject;
				cut.removeEventListener(ProgressEvent.PROGRESS, cutProgress);
				cut.removeEventListener(Event.COMPLETE, cutComplete);

				if(processlist.length > 0){
					processlist.shift();
				}

				processNext();
			}
		}

		public function cutCancel():void{
			var main:* = this.parent;

			if(processlist.length > 0){
				var current:CutObject = processlist.shift();
				current.stop();
				current.processed = false;
			}

			current.pathlist[0].dirty = true;
			current.pathlist[0].camdirty = true;

			processlist = new Array();
		}

		public function processFile(pd:ProgressDialog, svgxml:XML):void{
			progressdialog = pd;
			pd.init(1);

			var processor:ProcessFile = new ProcessFile(this,pathlist,svgxml);
			processor.addEventListener(ProgressEvent.PROGRESS, processProgress);
			processor.addEventListener(Event.COMPLETE, processComplete);
			addChild(processor);
			processor.start();
		}

		public function processProgress(e:ProgressEvent):void{
			progressdialog.setProgress(e.bytesLoaded/e.bytesTotal);
		}

		public function processComplete(e:Event):void{
			for each(var path:Path in pathlist){
				// check for self-overlap (beginning and end points are within tolerances)
				if(path.active == true){
					if(Global.withinTolerance(path.seglist[0].p1,path.seglist[path.seglist.length-1].p2)){
						path.seglist[0].p1 = path.seglist[path.seglist.length-1].p2;
					}
				}
			}

			var processor:ProcessFile = e.target as ProcessFile;
			processor.removeEventListener(ProgressEvent.PROGRESS, processProgress);
			processor.removeEventListener(Event.COMPLETE, processComplete);

			loadCuts(processor.svgxml);

			progressdialog.stopDialog();
			removeChild(processor);

			redraw();
		}

		// add cutobjects from the raw svg xml file
		public function loadCuts(svg:XML):void{
			var metadata:XML;

			for each(var child:XML in svg.*) {
				if(child.localName() == "metadata"){
					metadata = child;
				}
			}

			if(metadata == null){
				return;
			}

			for each(child in metadata.*){
				if(child.localName() == "cutobject"){
					loadCutObject(child);
				}
			}

			// remove path names after they have been used (they will interfere with future load operations)
			for each(var path:Path in pathlist){
				path.name = '';
			}
		}

		protected function loadCutObject(cutobject:XML):void{
			var children:Array = new Array();

			// parse children first

			for each(var child:XML in cutobject.*){
				if(child.localName() == "path"){
					var id:String = String(child.text());
					for each(var path:Path in pathlist){
						if(path.name == id){
							children.push(path);
						}
					}
				}
			}

			if(children.length == 0){
				return;
			}

			var cut:CutObject;
			var type:String = cutobject.@type;

			if(type == "profile"){
				cut = new ProfileCutObject();
			}
			else if(type == "pocket"){
				cut = new PocketCutObject();
			}
			else if(type == "followpath"){
				cut = new FollowPathCutObject();
			}
			else if(type == "drill"){
				cut = new DrillCutObject();
			}

			var cutname:String = unescape(cutobject.@name);

			if(cutname == ""){
				cutname = "unnamed operation";
			}

			cut.name = cutname;
			cut.safetyheight = cutobject.@safetyheight;
			cut.stocksurface = cutobject.@stocksurface;
			cut.targetdepth = cutobject.@targetdepth;
			cut.stepover = cutobject.@stepover;
			cut.stepdown = cutobject.@stepdown;
			cut.feedrate = cutobject.@feedrate;
			cut.plungerate = cutobject.@plungerate;

			cut.outside = (cutobject.@outside == "true" ? true : false);
			cut.dir = (cutobject.@direction == "2" ? 2 : 1);

			cut.center = (cutobject.@center == "true" ? true : false);
			cut.spacing = cutobject.@spacing;

			cut.tooldiameter = cutobject.@tooldiameter;
			cut.roughingclearance = cutobject.@roughingclearance;

			if(Global.unit == "in" && cutobject.@unit == "metric"){
				// mm to inch
				cut.safetyheight /= 25.4;
				cut.stocksurface /= 25.4;
				cut.targetdepth /= 25.4;
				cut.stepdown /= 25.4;
				cut.feedrate /= 25.4;
				cut.plungerate /= 25.4;

				// cm to inch
				cut.tooldiameter /= 2.54;
				cut.roughingclearance /= 2.54;

				cut.spacing /= 2.54;
			}
			else if(Global.unit == "cm" && cutobject.@unit == "imperial"){
				// inch to mm
				cut.safetyheight *= 25.4;
				cut.stocksurface *= 25.4;
				cut.targetdepth *= 25.4;
				cut.stepdown *= 25.4;
				cut.feedrate *= 25.4;
				cut.plungerate *= 25.4;

				// inch to cm
				cut.tooldiameter *= 2.54;
				cut.roughingclearance *= 2.54;

				cut.spacing *= 2.54;
			}

			for each(path in children){
				path.zeroOrigin();
			}

			cut.pathlist = children;

			addCut(cut);
		}

		// do a separate operation on each selected path
		public function separateSelected():void{

			var len:int = pathlist.length;

			for(var i:int=0; i<len; i++){
				if(pathlist[i].active == true){
					var paths:Array = pathlist[i].separate();
					if(paths.length > 0){
						// check cutlist (we must replace the path in the cutobject)
						for(var j:int=0; j<cutlist.length; j++){
							var index:int = cutlist.pathlist.indexOf(pathlist[i]);
							if(index != -1){
								cutlist.pathlist.splice(index,1,paths);
							}
						}
						for each(var p:Path in paths){
							p.name = pathlist[i].name;
						}
						pathlist.splice(i,1);
						addPaths(paths);
						i--;
						len--;
					}
				}
			}
		}

		/*public function mergeSelected():void{

			for(var i:int=0; i<pathlist.length; i++){
				var path:Path = pathlist[i];
				// check for overlapping points between this and every other path
				for(var j:int = i+1; j<pathlist.length; j++){
					var path2:Path = pathlist[j];
					if(path != path2 && path.active == true && path2.active == true){
						if(Global.withinTolerance(path.seglist[0].p1,path2.seglist[0].p1,0.1)){
							path.reversePath();
							path.resetSegments();
							path.mergePath(path2,path.seglist[path.seglist.length-1].p2,false);
							j = i;
						}
						else if(Global.withinTolerance(path.seglist[0].p1,path2.seglist[path2.seglist.length-1].p2,0.1)){
							path2.mergePath(path,path2.seglist[path2.seglist.length-1].p2,false);
							i--;
							break;
						}
						else if(Global.withinTolerance(path.seglist[path.seglist.length-1].p2,path2.seglist[0].p1,0.1)){
							path.mergePath(path2,path.seglist[path.seglist.length-1].p2,false);
							j = i;
						}
						else if(Global.withinTolerance(path.seglist[path.seglist.length-1].p2,path2.seglist[path2.seglist.length-1].p2,0.1)){
							path2.reversePath();
							path.mergePath(path2,path.seglist[path.seglist.length-1].p2,false);
							j = i;
						}
					}
				}
			}

			for each(path in pathlist){
				// first check for self-overlap (beginning and end points are within tolerances)
				if(path.active == true){
					if(Global.withinTolerance(path.seglist[0].p1,path.seglist[path.seglist.length-1].p2)){
						path.seglist[0].p1 = path.seglist[path.seglist.length-1].p2;
					}
					//path.joinDoubles(1, true);
				}
			}
		}*/

		public function pathsOnTop():void{
			for each(var path:Path in pathlist){
				addChild(path);
			}
		}

		// nesting functions start here
		public function startNest(pd:ProgressDialog, directions:int, gap:Number, group:Boolean, groupprofile:Boolean):Boolean{
			progressdialog = pd;

			if(nestpath == null){
				return false;
			}

			if(cutlist.length < 2){
				return false;
			}

			if(nest != null && contains(nest)){
				removeChild(nest);
			}

			nest = new Nest(nestpath, cutlist.slice(), directions, gap, group, groupprofile);
			addChild(nest);

			for(var i:int=0; i<cutlist.length; i++){
				addChild(cutlist[i]);
			}

			nest.addEventListener(ProgressEvent.PROGRESS, nestProgress);

			nest.start();

			if(nest.underlimit == true){
				finishNest();
				return false;
			}

			progressdialog.init(1);

			return true;
		}

		private function nestProgress(e:ProgressEvent):void{
			var nestprogress:Number = Math.min(e.bytesLoaded/e.bytesTotal,1);
			progressdialog.setProgress(nestprogress);
		}

		// stop nest and apply transformations
		public function finishNest():void{
			nest.stop();
			nest.removeEventListener(ProgressEvent.PROGRESS, nestProgress);

			var fittest:Individual = nest.fittest;

			if(fittest){
				// apply transformation
				var data:Array = fittest.data;

				var region:Rectangle = nest.blank.getBounds(nest);

				var processed:Array = new Array();

				for(var i:int=0; i<data.length; i++){
					if(!data[i].failed){
						var cutobject:* = nest.cutlist[data[i].index];

						// the clumped nest object (cutobject) is represented as a tree using the displayobject dom
						// we have to flatten it into an array
						var cutarray:Array = new Array(cutobject);
						var index:int = 0;
						while(index < cutarray.length){
							while(cutarray[index].numChildren > 0){
								var childobject:* = cutarray[index].getChildAt(0);
								if(childobject is CutObject){
									cutarray.push(childobject);
								}
								cutarray[index].removeChildAt(0);
							}
							index++;
						}

						// gather all associated paths, and ensure that there are no repeats
						var nestarray:Array = new Array();

						for(var j:int=0; j<cutarray.length; j++){
							for(var k:int=0; k<cutarray[j].pathlist.length; k++){
								if(nestarray.indexOf(cutarray[j].pathlist[k]) == -1 && processed.indexOf(cutarray[j].pathlist[k]) == -1){
									nestarray.push(cutarray[j].pathlist[k]);
									processed.push(cutarray[j].pathlist[k]);
								}
							}
						}

						// apply a matrix transform to each path in nest array
						var matrix:Matrix = new Matrix();
						matrix.rotate(-data[i].rotation*(Math.PI/180));

						// account for translation caused by rotation
						matrix.translate(-data[i].x/Global.zoom, data[i].y/Global.zoom);

						// account for bounding box of blank
						matrix.translate(region.x/Global.zoom, -(region.y+region.height-1)/Global.zoom);

						// position within blank
						matrix.translate(data[i].i/(Global.zoom*nest.scale), (-data[i].j+nest.blankbitmap.height)/(Global.zoom*nest.scale));
						for(j=0; j<nestarray.length; j++){
							nestarray[j].matrixTransform(matrix);
						}
					}
				}
			}
			nest.finish();
			removeChild(nest);

			for(i=0; i<cutlist.length; i++){
				while(cutlist[i].numChildren > 0){
					cutlist[i].removeChildAt(0);
				}
				addChild(cutlist[i]);

				/*cutlist[i].docx = 0;
				cutlist[i].docy = 0;
				cutlist[i].x = 0;
				cutlist[i].y = 0;*/

				cutlist[i].processed = false;
				cutlist[i].rotation = 0;
				cutlist[i].pathlist[0].dirty = true;
				cutlist[i].pathlist[0].camdirty = true;
				cutlist[i].graphics.clear();
			}

			redraw();
		}

		// adds tabs to selected (and calculated) profile operations
		public function addTabsSelected(spacing:Number, tabwidth:Number, tabheight:Number):void{
			for(var i:int=0; i<cutlist.length; i++){
				if(cutlist[i].active == true && cutlist[i] is ProfileCutObject && cutlist[i].processed == true){
					cutlist[i].addTabs(spacing, tabwidth, tabheight);
				}
			}
		}

		// move the selected cutobjects outside of the bounding box of the deselected cutobjects
		public function shiftActive():void{
			var inactive:Array = new Array();
			var active:Array = new Array();

			for(var i:int = 0; i<cutlist.length; i++){
				if(cutlist[i].active == true){
					active.push(cutlist[i]);
				}
				else{
					inactive.push(cutlist[i]);
				}
				// some problems with accounting for docx/y, for now just reset all to zero
				cutlist[i].zeroOrigin();
				cutlist[i].pathlist[0].dirty = true;
				cutlist[i].pathlist[0].camdirty = true;
			}

			var irect:Rectangle = getExactBounds(inactive);
			var arect:Rectangle = getExactBounds(active);

			/*var p:Path = new Path();
			var seg1:Segment = new Segment(new Point(irect.x,irect.y),new Point(irect.x,irect.y+irect.height));
			var seg2:Segment = new Segment(seg1.p2,new Point(irect.x+irect.width,irect.y+irect.height));
			var seg3:Segment = new Segment(seg2.p2,new Point(irect.x+irect.width,irect.y));
			var seg4:Segment = new Segment(seg3.p2,new Point(irect.x,irect.y));

			p.addSegment(seg1);
			p.addSegment(seg2);
			p.addSegment(seg3);
			p.addSegment(seg4);

			addPath(p);*/

			var diff:Number = 0;

			if(arect.x >= irect.x && arect.x <= irect.x + irect.width){
				diff = irect.x + irect.width - arect.x;
			}
			else if(irect.x >= arect.x && irect.x <= arect.x + arect.width){
				diff = arect.x + arect.width - irect.x;
				diff = -diff;
			}

			var processed:Array = new Array();

			for(i=0; i<active.length; i++){
				for(var j:int=0; j<active[i].pathlist.length; j++){
					var path:Path = active[i].pathlist[j];
					if(processed.indexOf(path) == -1){
						path.docx += diff;
						path.dirty = true;
						path.camdirty = true;
						processed.push(path);
					}
				}
			}

			redraw();
		}

		// get exact bounds of the list of cutobjects, taking into account whether they are processed
		private function getExactBounds(list:Array):Rectangle{
			var minx:Number;
			var miny:Number;
			var maxx:Number;
			var maxy:Number;

			// find bounding box of deselected cutpaths
			for(var i:int=0; i<list.length; i++){
				var lminx:Number = NaN;
				var lminy:Number = NaN;
				var lmaxx:Number = NaN;
				var lmaxy:Number = NaN;

				var children:Array = list[i].rootpath.getChildren();
				for(var j:int=0; j<children.length; j++){
					var rect:Rectangle = children[j].getExactBounds();
					if(isNaN(lminx) || rect.x < lminx){
						lminx = rect.x;
					}
					if(isNaN(lmaxx) || rect.x + rect.width > lmaxx){
						lmaxx = rect.x + rect.width;
					}
					if(isNaN(lminy) || rect.y < lminy){
						lminy = rect.y;
					}
					if(isNaN(lmaxy) || rect.y + rect.height > lmaxy){
						lmaxy = rect.y + rect.height;
					}
				}

				if(list[i] is ProfileCutObject){
					if(list[i].processed == true){
						lmaxx += 0.5*list[i].tooldiameter;
						lmaxy += 0.5*list[i].tooldiameter;
						lminx -= 0.5*list[i].tooldiameter;
						lminy -= 0.5*list[i].tooldiameter;
					}
					else{
						lmaxx += list[i].tooldiameter;
						lmaxy += list[i].tooldiameter;
						lminx -= list[i].tooldiameter;
						lminy -= list[i].tooldiameter;
					}
				}
				else if(list[i] is FollowPathCutObject){
					lmaxx += 0.5*list[i].tooldiameter;
					lmaxy += 0.5*list[i].tooldiameter;
					lminx -= 0.5*list[i].tooldiameter;
					lminy -= 0.5*list[i].tooldiameter;
				}

				if(isNaN(minx) || lminx < minx){
					minx = lminx;
				}
				if(isNaN(maxx) || lmaxx > maxx){
					maxx = lmaxx;
				}
				if(isNaN(miny) || lminy < miny){
					miny = lminy;
				}
				if(isNaN(maxy) || lmaxy > maxy){
					maxy = lmaxy;
				}
			}

			return new Rectangle(minx,miny,maxx-minx,maxy-miny);
		}
	}

}