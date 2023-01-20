class CodeBuilder {
    var data:FunctionData;

    public function new(data:FunctionData) {
        this.data = data;
    }

    public function build():Void {
    }

}

@:structInit class FunctionData {
	public final args:Array<String>;
}
