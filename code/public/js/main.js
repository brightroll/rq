domready(function() {
  var a2hObj = ansi2html.ansi_to_html_obj();

  var CONTINUE_STATES = ["prep", "que", "run"];
  var last_done = 0;
  var last_file_start = 0;
  var last_fragment = "";

  window.onscroll = updateFilePos;
  window.onresize = updateFilePos;

  function updateFilePos() {
    // Set the filepos indicators
    var filepos_top = document.getElementById("filepos-top");
    var filepos_bot = document.getElementById("filepos-bot");
    var filepos_end = document.getElementById("filepos-end");

    var ansitxt = document.getElementById("ansitxt");
    var lines = ansitxt.innerHTML.split("\n").length - 1;
    var height = document.body.scrollHeight;

    var line_height = height / lines;
    var top_line = Math.floor(document.body.scrollTop / line_height);
    var view_lines = Math.floor(document.body.clientHeight / line_height);

    filepos_top.innerHTML = 1 + top_line;
    filepos_bot.innerHTML = 1 + top_line + view_lines;
    filepos_end.innerHTML = lines;
  }

  function process(txt) {

    if (txt.length == 0) return;

    var new_block = "";
    var new_fragment = "";

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

    // Delete the last fragment we're about to replace it with a larger block
    var span_last_fragment = document.getElementById("last_fragment");
    if (span_last_fragment) span_last_fragment.parentNode.removeChild(span_last_fragment);

    var block = a2hObj.ansi_to_html(a2hObj.linkify(a2hObj.escape_for_html(new_block)));
    if (block) {
      // console.log("block: " + block);
      var ansitxt = document.getElementById("ansitxt");
      ansitxt.innerHTML += block;
    }

    // Now preserve state of a2hObj for multi-line ansi
    // and do throw-away processing of fragment
    var a2hObjFrag = Object.create(a2hObj);
    var fragment = a2hObjFrag.ansi_to_html(a2hObjFrag.linkify(a2hObjFrag.escape_for_html(new_fragment)));
    if (fragment) {
      // console.log("fragment: " + fragment);
      var new_last_fragment = document.createElement("span");
      new_last_fragment.id = "last_fragment";
      new_last_fragment.innerHTML = fragment;

      var ansitxt = document.getElementById("ansitxt");
      ansitxt.insertBefore(new_last_fragment, ansitxt.nextSibling);
    }

    // Scroll to the bottom if the box is checked
    var tail = document.getElementById("filepos-tail");
    if (tail && tail.checked) {
      window.scrollTo(0, document.body.scrollHeight);
    }

    // Whether we scroll or not, update the position and line count
    updateFilePos();
  }

  function checkState() {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", config.state_path, true);
    xmlhttp.setRequestHeader("Cache-Control", "no-cache");
    xmlhttp.onreadystatechange = function() {
      if (xmlhttp.readyState == 4 && xmlhttp.status == 200) {
        // console.log(xmlhttp.responseText);
        var state = JSON.parse(xmlhttp.responseText)[0];
        if (CONTINUE_STATES.indexOf(state) != -1) {
          window.setTimeout(function () { nextChunk(); }, 1000);
        } else {
          last_done = last_done + 1;
          if (last_done < 2) {
            window.setTimeout(function () { nextChunk(); }, 1000);
          } else {
            console.log("Completed loading file.");
          }
        }
      }
      else if (xmlhttp.readyState == 4) {
        // Try again in 1 second
        window.setTimeout(function () { checkState(); }, 1000);
      }
    };
    xmlhttp.send();
  }

  function nextChunk() {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", config.tail_path, true);
    var range_query = "bytes=" + last_file_start + "-" ;
    // console.log("Range: " + range_query);
    xmlhttp.setRequestHeader("Range", range_query);
    xmlhttp.setRequestHeader("Cache-Control", "no-cache");
    xmlhttp.onreadystatechange = function() {
      if (xmlhttp.readyState == 4 && xmlhttp.status == 206) {
        process(xmlhttp.response);
        var range = xmlhttp.getResponseHeader("Content-Range");
        var range_parts = range.match(/bytes (\d+)-(\d+)\/(\d+)/);
        // console.log(range_parts);
        var r_start = parseInt(range_parts[1]);
        var r_max_end = parseInt(range_parts[2]);
        var r_actual_end = parseInt(range_parts[3]);

        last_file_start = 1 + (r_max_end < r_actual_end ? r_max_end : r_actual_end);
        window.setTimeout(function () { nextChunk(); }, 100);
        last_done = 0;
      }
      else if (xmlhttp.readyState == 4) {
        // Try again in 1 second
        window.setTimeout(function () { checkState(); }, 1000);
      }
    };
    xmlhttp.send();
  };

  nextChunk();
});
