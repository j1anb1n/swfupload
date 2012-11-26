
package
{
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.Loader;
	import flash.errors.IOError;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.ProgressEvent;
	import flash.events.IOErrorEvent;
	import flash.events.EventDispatcher;
	import flash.events.TimerEvent;
	import flash.filters.BitmapFilter;
	import flash.filters.BitmapFilterQuality;
	import flash.filters.BlurFilter;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.net.FileReference;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	//import cmodule.jpegencoder.CLibInit;
	import EncodeCompleteEvent;
	import EncodeProgressEvent;
	import ExternalCall
	/*
	Technique adapted from Kun Janos (http://kun-janos.ro/blog/?p=107)
	*/
	public class ImageResizer extends EventDispatcher
	{
		private var file:FileItem = null;
		private var targetWidth:Number = 0;
		private var targetHeight:Number = 0;
		private var newWidth:Number = 1;
		private var newHeight:Number = 1;
		private var encoder:Number = ImageResizer.JPEGENCODER;
		private var quality:Number = 100;
		private var allowEnlarging:Boolean = true;
		private var allowSmaller:Boolean = true;
		//private var ba:ByteArray;
		//private var baOut:ByteArray;

		public static const JPEGENCODER:Number = -1;
		public static const PNGENCODE:Number = -2;

		//private static var cLibEncoder:Object = null;

		public function ImageResizer(file:FileItem, targetWidth:Number, targetHeight:Number, encoder:Number, quality:Number = 100, allowEnlarging:Boolean = true, allowSmaller:Boolean = true) {
			this.file = file;
			this.targetHeight = targetHeight;
			this.targetWidth = targetWidth;
			this.debug('set encode to' + encoder);
			this.encoder = encoder;
			this.quality = quality;
			this.allowEnlarging = allowEnlarging;
			this.allowSmaller = allowSmaller;

			if (this.encoder != ImageResizer.JPEGENCODER && this.encoder != ImageResizer.PNGENCODE) {
				this.encoder = ImageResizer.JPEGENCODER;
			}
			if (this.quality < 0 || this.quality > 100) {
				this.quality = 100;
			}
		}
		private function debug(message:String):void {
			ExternalCall.Debug('SWFUpload.debug', 'ImageResizer::' + message);
		}

		public function ResizeImage():void {
			try {
				var timer:Timer = new Timer(3000);
				var t:ImageResizer = this;
				timer.addEventListener(TimerEvent.TIMER, function ():void {
					t.debug('error in loading file');
					timer.stop();
					dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, 'error in loading file'));
					t.file.file_reference.removeEventListener(Event.COMPLETE, t.fileLoad_Complete);
					t.file = null;
				});
				this.file.file_reference.addEventListener(Event.COMPLETE, this.fileLoad_Complete);
				this.file.file_reference.addEventListener(Event.COMPLETE, function ():void {
					timer.stop();
				});
				this.file.file_reference.load();
				timer.start();
			} catch (ex:Error) {
				this.debug('error in ResizeImage: ' + ex.message);
				this.file.file_reference.removeEventListener(Event.COMPLETE, this.fileLoad_Complete);
				dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, "Loading from file reference: " + ex.message));
				this.file = null;
			}
		}
		private function fileLoad_Complete(event:Event):void {
			try {
				this.debug('file load');
				event.target.removeEventListener(Event.COMPLETE, this.fileLoad_Complete);
				var loader:Loader = new Loader();
				// Load the image data, resizing takes place in the event handler
				loader.contentLoaderInfo.addEventListener(Event.COMPLETE, this.loader_Complete);
				loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.loader_Error);
				loader.loadBytes(FileReference(event.target).data);
			} catch (ex:Error) {
				loader.removeEventListener(Event.COMPLETE, this.loader_Complete);
				dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, "Loading Loader" + ex.message));
				this.file = null;
			}
		}
		private function loader_Error(event:IOErrorEvent):void {
			try {
				event.target.removeEventListener(Event.COMPLETE, this.loader_Complete);
				event.target.removeEventListener(IOErrorEvent.IO_ERROR, this.loader_Error);
			} catch (ex:Error) {}

			dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, "Resizing: " + event.text));
		}

		private function loader_Complete(event:Event):void {
			try {
				this.debug('loader_complete');
				var bytes:ByteArray;

				event.target.removeEventListener(Event.COMPLETE, this.loader_Complete);
				event.target.removeEventListener(IOErrorEvent.IO_ERROR, this.loader_Error);

				var loader:Loader = Loader(event.target.loader);

				var contentType:String = loader.contentLoaderInfo.contentType;
				this.setEncoder(contentType);

				// Calculate the new image size
				var targetRatio:Number = this.targetWidth / this.targetHeight;
				var imgRatio:Number = loader.width / loader.height;
				this.newHeight = (targetRatio > imgRatio) ? this.targetHeight : Math.min(this.targetWidth / imgRatio, this.targetHeight);
				this.newWidth = (targetRatio > imgRatio) ? Math.min(imgRatio * this.targetHeight, this.targetWidth) : this.targetWidth;

				// Get the image data
				var bmp:BitmapData = Bitmap(loader.content).bitmapData;

				loader.unload();
				loader = null;

				// If enlarging is not allowed but the new width causes enlarging then adjust the dimensions
				if (!this.allowEnlarging && (this.newWidth > bmp.width || this.newHeight > bmp.height)) {
					this.newWidth = bmp.width;
					this.newHeight = bmp.height;
				}

				if (!this.allowEnlarging && !this.allowSmaller) {
					this.newHeight = bmp.height;
					this.newWidth  = bmp.width;
				}

				if (this.newWidth < bmp.width || this.newHeight < bmp.height || this.IsTranscoding(contentType)) {
					// Apply the resizing
					var matrix:Matrix = new Matrix();
					matrix.identity();
					matrix.createBox(this.newWidth / bmp.width, this.newHeight / bmp.height);

					var resizedBmp:BitmapData = new BitmapData(this.newWidth, this.newHeight, true, 0x000000);
					resizedBmp.draw(bmp, matrix, null, null, null, true);

					bmp.dispose();

					var encoder:Object = null;
					if (this.encoder == ImageResizer.PNGENCODE) {
						encoder = new PNGEncoder(PNGEncoder.TYPE_SUBFILTER, 1);
					} else {
						encoder = new AsyncJPEGEncoder(this.quality, 0, 100);
					}

					encoder.addEventListener(EncodeCompleteEvent.COMPLETE, this.EncodeCompleteHandler);
					encoder.addEventListener(EncodeProgressEvent.PROGRESS, this.eventProgress);
					encoder.addEventListener(ErrorEvent.ERROR, this.EncodeErrorHandler);
					encoder.encode(resizedBmp);
				} else {
					// Just send along the unmodified data
					dispatchEvent(new ImageResizerEvent(ImageResizerEvent.COMPLETE, this.file.file_reference.data, this.encoder));
				}

			} catch (ex:Error) {
				dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, "Resizing: " + ex.message));
			}

			this.file = null;
		}

		private function IsTranscoding(type:String):Boolean {
			if (type === "image/jpeg" || type === '"image/png') {
				return true;
			} else {
				return false;
			}
		}

		private function setEncoder(type:String):Boolean {
			if (type === "image/jpeg") {
				this.encoder === ImageResizer.JPEGENCODER;
				return true;
			}
			if (type === 'image/png') {
				this.encoder === ImageResizer.PNGENCODE;
				return true;
			}
			return false;
		}

		private function EncodeErrorHandler(e:ErrorEvent):void {
			dispatchEvent(e);
		}

		/*
		private function compressFinished(out:ByteArray):void {
			this.baOut.position = 0;
			this.ba.clear();

			this.EncodeCompleteHandler(new EncodeCompleteEvent(baOut));
		}
		*/

		private function EncodeCompleteHandler(e:EncodeCompleteEvent):void {
			dispatchEvent(new ImageResizerEvent(ImageResizerEvent.COMPLETE, e.data, this.encoder));
		}

		private function eventProgress(e:EncodeProgressEvent):void {
			dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, e.doneLines, e.totalLines));
			// (e.bytesLoaded / e.bytesTotal);
		}

	}

}