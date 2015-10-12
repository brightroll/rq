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

  rq_http_request(config.main_path + ".json", function(s, b) {
    // Process the result
    if (s == 200) {
      var responseJSON = JSON.parse(b);
      displayQueues(responseJSON);
    }
    return 900;
  });
});
