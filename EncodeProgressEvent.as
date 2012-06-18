package
{
	import flash.events.Event;
	import flash.utils.ByteArray;
	
	public class EncodeProgressEvent extends Event
	{
		public static const PROGRESS:String='encodeProgressEvent';
		
		private var done:int;
		private var total:int;
		
		public function EncodeProgressEvent(done:int,total:int, bubbles:Boolean=false, cancelable:Boolean=false)
		{
			super(PROGRESS, bubbles, cancelable);
			
			this.done=done;
			this.total=total;
			
		}
		
		public function get doneLines():int
		{
			return done;
		}
		
		public function get totalLines():int
		{
			return total;
		}
		
		override public function clone() : Event
		{
			return new EncodeProgressEvent(done,total,bubbles,cancelable);
		}
	}
}