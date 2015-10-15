domready(function() {
  var shushForms = document.getElementsByClassName('shush-form');
  for (var i = 0; i < shushForms.length; i++) {
    shushForms[i].addEventListener('submit', function (e) {
        this.getElementsByClassName('shush-button').disabled = true;
    });
  }

  // Update the page and all queue rows
  function displayQueues(queues) {
    document.getElementById("ping").innerHTML = queues["ping"];
    document.getElementById("pid").innerHTML = queues["pid"];
    document.getElementById("uptime").innerHTML = queues["uptime"];

    var s = document.getElementById("status");
    if (queues["status"] == "UP") {
      s.innerHTML = "UP";
      s.className = "green";
    } else {
      s.innerHTML = queues["status"];
      s.className = "red";
    }

    for (var i of ["prep_size", "que_size", "run_size", "done_size", "err_size", "relayed_size"]) {
      var e = document.getElementById(i);
      if (e) e.innerHTML = queues[i];
    }

    for (var state in queues["messages"]) {
      var list = document.getElementById("list-" + state);
      if (list) {
        // Post the date prefix above each day's messages
        var last_date = "";
        // Zap everything in the list and then populate it again.
        // TODO: avoid refreshing everything, DOM redraws are a pain.
        list.innerHTML = "";
        queues["messages"][state].sort(function(a, b) {
          return a["msg_id"] < b["msg_id"];
        });
        queues["messages"][state].forEach(function(msg, idx, ary) {
          var id_split = msg["msg_id"].split(".");
          var date = id_split.shift();
          msg["_short_msg_id"] = id_split.join(".");

          if (date != last_date) {
            var t = document.getElementById("template-separator");
            var n = t.cloneNode(true);
            var l = n.getElementsByClassName("template-date");
            if (l && l[0]) {
              l[0].innerHTML = date;
            }
            last_date = date;
            list.appendChild(n);
          }

          var t = document.getElementById("template-" + state);
          var n = t.cloneNode(true);
          var l = n.getElementsByClassName("template-link");
          if (l && l[0]) {
            l[0].href = config.queue_path + "/" + msg["msg_id"];
            l[0].innerHTML = msg["_short_msg_id"];
          }
          var l = n.getElementsByClassName("template-seconds");
          if (l && l[0]) {
            l[0].innerHTML = msg["due"] - queues["time"];
          }
          var l = n.getElementsByClassName("template-status");
          if (l && l[0]) {
            l[0].innerHTML = msg["status"];
          }
          var l = n.getElementsByClassName("template-dest");
          if (l && l[0]) {
            l[0].href = msg["dest"];
            l[0].innerHTML = msg["dest"];
            l[0].style.display = "block";
          }
          var l = n.getElementsByClassName("template-new_msg");
          if (l && l[0]) {
            l[0].href = msg["new_msg"];
            l[0].innerHTML = msg["new_msg"];
          }
          var l = n.getElementsByClassName("template-form");
          // Iterate because there may be several forms
          for (var pos = 0; pos < l.length; pos++) {
            l.item(pos).action = msg["dest"] + "/" + msg["msg_id"];
          }
          list.appendChild(n);
        });
      }
    }
  }

  rq_http_request(config.queue_path + ".json", function(s, b) {
    // Process the result
    if (s == 200) {
      var responseJSON = JSON.parse(b);
      displayQueues(responseJSON);
    }
    return 900;
  });
});

function show_toggle() {
  var cfg = document.getElementById('config');
  if (cfg.className.indexOf('hidden') >= 0) {
    cfg.className = cfg.className.replace('hidden', '').replace(/\s+$/, "");
  } else {
    cfg.className += ' hidden';
  }
  return false;
}
