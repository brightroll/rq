domready(function() {

  function processRow(row, idx, arr) {
    console.info(row);
    for (var c in row['counts']) {
      var len = row['counts'][c].toString().length;
      var justy = row['counts'][c] + " ".repeat(len < 4 ? 4 - len : 0);
      document.getElementById(c + "-" + row['name']).innerHTML = justy;
    }
  }

  function nextUpdate() {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", "/q.json", true);
    xmlhttp.setRequestHeader("Cache-Control", "no-cache");
    xmlhttp.onreadystatechange = function() {
      // Process the result
      if (xmlhttp.readyState == 4 && xmlhttp.status == 200) {
        var responseJSON = JSON.parse(xmlhttp.responseText)
        responseJSON.forEach(processRow);

        // Fetch again in 10 seconds
        window.setTimeout(function () { nextUpdate(); }, 10000);
      }
    };
    xmlhttp.send();
  };

  nextUpdate();
});
