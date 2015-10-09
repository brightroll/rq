domready(function() {
  // Update the page and all queue rows
  function displayQueues(queues) {
    document.getElementById("status").innerHTML = queues["status"];
    document.getElementById("ping").innerHTML = queues["ping"];
    document.getElementById("pid").innerHTML = queues["pid"];
    document.getElementById("uptime").innerHTML = queues["uptime"];
    document.getElementById("version").innerHTML = queues["version"];
    document.getElementById("time").innerHTML = queues["time"];

    for (var row of queues["queues"]) {
      document.getElementById("ping-" + row["name"]).innerHTML = row["ping"];
      document.getElementById("pid-" + row["name"]).innerHTML = row["pid"];
      document.getElementById("uptime-" + row["name"]).innerHTML = row["uptime"];

      var s = document.getElementById("status-" + row["name"]);
      if (row["status"] == "UP") {
        s.innerHTML = "UP";
        s.className = "green";
      } else {
        s.innerHTML = row["status"];
        s.className = "red";
      }

      for (var c in row["counts"]) {
        var len = row["counts"][c].toString().length;
        var justy = row["counts"][c] + " ".repeat(len < 4 ? 4 - len : 0);
        document.getElementById(c + "-" + row["name"]).innerHTML = justy;
      }
    }
  }

  // Fetch q.json
  function nextUpdate() {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", config.main_path + ".json", true);
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
