function rq_http_request(url, callback) {
  function nextUpdate() {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", url, true);
    xmlhttp.setRequestHeader("Cache-Control", "no-cache");
    xmlhttp.onreadystatechange = function() {
      // State 4 means "totally done"
      if (xmlhttp.readyState == 4) {
        // Call the callback
        var next = callback(xmlhttp.status, xmlhttp.responseText);
        // Schedule the next request
        if (next) {
          window.setTimeout(function () { nextUpdate(); }, next);
        }
      }
    }
    xmlhttp.send();
  };

  // Schedule the first request
  nextUpdate();
}
