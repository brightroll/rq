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
        // Zap everything in the list and then populate it again.
        // TODO: avoid refreshing everything, DOM redraws are a pain.
        list.innerHTML = "";
        for (var msg of queues["messages"][state]) {
          var t = document.getElementById("template-" + state);
          var n = t.cloneNode(true);
          var l = n.getElementsByClassName("template-link");
          if (l && l[0]) {
            l[0].href = config.queue_path + "/" + msg["msg_id"];
            l[0].innerHTML = msg["msg_id"];
          }
          var l = n.getElementsByClassName("template-seconds");
          if (l && l[0]) {
            l[0].innerHTML = msg["due"] - queues["time"];
          }
          var l = n.getElementsByClassName("template-status");
          if (l && l[0]) {
            l[0].innerHTML = msg["status"];
          }
          var l = n.getElementsByClassName("template-new_msg");
          if (l && l[0]) {
            l[0].href = msg["new_msg"];
            l[0].innerHTML = msg["new_msg"];
          }
          var l = n.getElementsByClassName("template-form");
          // FIXME: "for (var f of l)" didn't work!?
          if (l && l[0]) {
            l[0].action = msg["dest"] + "/" + msg["msg_id"];
          }
          if (l && l[1]) {
            l[1].action = msg["dest"] + "/" + msg["msg_id"];
          }
          list.appendChild(n);
        }
      }
    /*

<% msgs = qc.messages({'state' => state, 'limit' => 50}) %>
<% grouped = {} %>
<% msgs.each do |msg| %>
  <% next if msg.nil? %>
  <% date, msg['_short_msg_id'] = msg['msg_id'].split('.', 2) %>
  <% grouped[date] ||= [] %>
  <% grouped[date] << msg %>
<% end %>
<% grouped.sort.reverse.each do |date, msgs| %>
  <h5><%= date %></h5>
  <ul>
  <% msgs.sort_by{ |m| m['msg_id'] }.reverse.each do |msg| %>
    <li>
    <a href="<%= "#{root}q/#{qc.name}/#{msg['msg_id']}" %>"><%= msg['_short_msg_id'] %></a>
    */
    }
  }

  // Fetch q.json
  function nextUpdate() {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", config.queue_path + ".json", true);
    xmlhttp.setRequestHeader("Cache-Control", "no-cache");
    xmlhttp.onreadystatechange = function() {
      // State 4 means "totally done"
      if (xmlhttp.readyState == 4) {
        // Schedule the next fetch
        window.setTimeout(function () { nextUpdate(); }, 900);

        // Process the result
        if (xmlhttp.status == 200) {
          var responseJSON = JSON.parse(xmlhttp.responseText);
          displayQueues(responseJSON);
        }
      }
    };
    xmlhttp.send();
  }

  // Schedule the first fetch
  nextUpdate();
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
