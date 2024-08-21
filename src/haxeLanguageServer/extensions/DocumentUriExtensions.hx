package haxeLanguageServer.extensions;

private final driveLetterPathRe = ~/^\/[a-zA-Z]:/;
private final uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;

/** ported from VSCode sources **/
function toFsPath(uri:DocumentUri):FsPath {
	if (!uriRe.match(uri.toString()) || uriRe.matched(2) != "file")
		throw 'Invalid uri: $uri';

	final path = uriRe.matched(5).urlDecode();
	if (driveLetterPathRe.match(path))
		return new FsPath(path.charAt(1).toLowerCase() + path.substr(2));
	else
		return new FsPath(path);
}

function isFile(uri:DocumentUri):Bool {
	return uri.toString().startsWith("file://");
}

function isUntitled(uri:DocumentUri):Bool {
	return uri.toString().startsWith("untitled:");
}

function isHaxeFile(uri:DocumentUri):Bool {
	return uri.toString().endsWith(".hx");
}

function isHxmlFile(uri:DocumentUri):Bool {
	return uri.toString().endsWith(".hxml");
}
