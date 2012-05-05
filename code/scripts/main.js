require(['config', 'ansi2html', "/scripts/jquery-1.7.2.min.js"],
        function(config, a2h) {

          var a2hObj = a2h.ansi_to_html_obj();
          var last_fragment = "";

          var path = config.path;
          var msg_path = config.msg_path + "/state.json";
          var BUFFER_SIZE = 8192;  // constant
          var last_done = 0;
          var last_file_start = 0;
          var last_file_end = BUFFER_SIZE;

          function clone(obj) {
            var p = Object.getPrototypeOf(obj);
            return Object.create(p);
          };

  function process(txt) {

    if (txt.length == 0) return;

    var new_fragment = "";
    var new_block = "";

    // Pull out new fragment

    // Look for last newline and adjust it to a usable value
    // (aka ++, since the split requires that value vs. actual idx)
    var last_newline_idx = txt.lastIndexOf("\n") + 1;
    if ((last_newline_idx != 0) && (last_newline_idx == txt.length)) {
      // no new fragment
      new_block = last_fragment + txt;
      new_fragment = last_fragment = "";
    } else {
      // new fragment
      new_block = last_fragment + txt.slice(0, last_newline_idx);
      new_fragment = last_fragment = txt.slice(last_newline_idx);
    }

    var t1 = a2hObj.escape_for_html(new_block);
    var t2 = a2hObj.linkify(t1);
    var t3 = a2hObj.ansi_to_html(t2);

    // Now preserve state of a2hObj for multi-line ansi
    // and do throw-away processing of fragment
    var a2hObjFrag = clone(a2hObj);
    var f1 = a2hObjFrag.escape_for_html(new_fragment);
    var f2 = a2hObjFrag.linkify(f1);
    var f3 = a2hObjFrag.ansi_to_html(f2);

    $("#last_fragment").remove();
    $("#ansitxt").append(t3);
    if (new_fragment.length > 0) {
      $("#ansitxt").append($('<span id="last_fragment"/>'));
      $("#last_fragment").append(f3);
    }
    //$("html, body").animate({ scrollTop: $("html, body").height() }, 500);
    $("#ansitxt").animate({ scrollTop: $("#ansitxt")[0].scrollHeight }, 500);
  }

  function checkState() {
    $.ajax({type: "GET",
             url: msg_path,
      })
     .done( function(data,textStatus,xhr) {
        var continue_states = ["prep", "que", "run"];
        var state = data[0];

        // if in a 'continue' state (as opposed to 'done', 'err', 'relayed'
        if (continue_states.indexOf(state) != -1) {
          window.setTimeout(function () { nextChunk(); }, 1000);
        } else {
          last_done = last_done + 1;
          if (last_done < 2) {
            window.setTimeout(function () { nextChunk(); }, 1000);
          }
        }
      })
     .fail( function(xhr,textStatus,errorThrown) {
        console.log('checkState');
        console.log(textStatus);
        console.log(xhr.status);
        console.log(errorThrown);
      })
     .always( function() {
        //console.log("complete2");
      });
  }

  function nextChunk() {
    var start = last_file_start;
    var end = last_file_end;

    $.ajax({type: "GET",
             url: path,
         headers: {"Range": "bytes=" + start + "-" + end}
      })
     .done( function(data,textStatus,xhr) {
        process(data);
        var range = xhr.getResponseHeader("Content-Range");
        //console.log(range);
        var parts = range.split(' ', 2);
        var rangeSize = parts[1].split('/', 2);
        var ranges = rangeSize[0].split('-', 2);

        last_file_start = parseInt(ranges[1]) + 1;
        last_file_end = last_file_start + BUFFER_SIZE;
        window.setTimeout(function () { nextChunk(); }, 100);
        last_done = 0;
      })
     .fail( function(xhr,textStatus,errorThrown) {
        if (xhr.status == 416) {
          // 416 Requested Range Not Satisfiable
          // Try again in 1 second
          window.setTimeout(function () { checkState(); }, 1000);
        } else {
          console.log(textStatus);
          console.log(xhr.status);
          console.log(errorThrown);
          //alert("error");
        }
      })
     .always( function() {
        //console.log("complete2");
      });
  };

  //console.log('this');
  nextChunk();
});
