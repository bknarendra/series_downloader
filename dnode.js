var torrentStream = require('torrent-stream');
var fs = require('fs');
var sys = require('sys')
var exec = require('child_process').exec;
function puts(error, stdout, stderr) { sys.puts(stdout) }
var ProgressBar = require('progress');
var Dropbox = require("dropbox");
//var redis = require("redis"),
//    redisClient = redis.createClient(port,host,{auth_pass: ''});
var client = new Dropbox.Client({
    key: "",
    secret: "",
    token: ""
});
torrent_magnet = process.argv[2]
console.log('starting to get torrent stream');
var engine = torrentStream(torrent_magnet);
var dropbox_auth_success = false;
files_downloaded = 0
engine.on('ready', function() {
  torrentLength = engine.torrent.length;
  var bar = new ProgressBar('  downloading [:bar] :percent :etas', {
    complete: '=',
    incomplete: ' ',
    width: 50,
    total: torrentLength
  });
  console.log('creating auth driver for dropbox'); 
  client.authDriver(new Dropbox.AuthDriver.NodeServer(8191));
  client.authenticate(function(error, client) {
    if (error) {
      console.log(error)
      return showError(error);
    }
    engine.files.forEach(function(file) {
      console.log('filename:', file.name);
      var stream = file.createReadStream();
      var _cursor = null;
      var so_far = 0;
      var file_length = file.length;
      stream.on('data', function(chunk) {
        if(_cursor==null || _cursor.offset == so_far){
          stream.pause();
          client.resumableUploadStep(chunk,_cursor,function(error,cursor){
            _cursor = cursor;
            //console.log(" cursor = %j",_cursor);
            stream.resume();
            if(_cursor != null && _cursor.offset == file_length){
              console.log("starting resumableUploadFinish");
              client.resumableUploadFinish(file.name,_cursor, function(error,metadata){
                console.log("upload for %s complete",file.name);
                //redisClient.del(file.name, function (err, reply) {});
                files_downloaded += 1;
                if(files_downloaded == engine.files.length){
                  engine.destroy();
                  console.log(metadata);
                  console.log("\n\nAll file downloads completed successfully");
                  exec("rm -rf /tmp/torrent-stream", puts);
                  process.exit(0);
                }
              });
            }
          });
          so_far += chunk.length;
          //redisClient.set(file.name, (so_far+" / "+torrentLength+" = "+((so_far/torrentLength)*100)+"%"), function (err, reply) {});
          console.log(so_far+" / "+file_length+" = "+((so_far/file_length)*100)+"%");
        }
      });
    });
  });
});

var showError = function(error) {
  switch (error.status) {
  case Dropbox.ApiError.INVALID_TOKEN:
    break;
  case Dropbox.ApiError.NOT_FOUND:
    break;
  case Dropbox.ApiError.OVER_QUOTA:
    break;
  case Dropbox.ApiError.RATE_LIMITED:
    break;
  case Dropbox.ApiError.NETWORK_ERROR:
    break;
  case Dropbox.ApiError.INVALID_PARAM:
  case Dropbox.ApiError.OAUTH_ERROR:
  case Dropbox.ApiError.INVALID_METHOD:
  default:
  }
};

