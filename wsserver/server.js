var express = require('express');
var app = express();
var expressWS = require('express-ws')(app);

var portNumber = 1234;
var messages = [];

app.listen(portNumber, function() {
  console.log(`Listening on port ${portNumber}`);
});

app.ws('/hello', function(websocket, request) {
  console.log('A client connected!');

  websocket.on('message', function(message) {
    console.log(`A client sent a message: ${message}`);
    websocket.send('Hallo, massa Tom!');
  });

  websocket.on('close', function(message) {
    console.log(`A client sent a message: ${message}`);
  });
});

app.ws('/chat', function(websocket, request) {
  console.log('A client connected to chat!');
  var intervalHandler = setInterval(function() {
    websocket.send(JSON.stringify(messages))
  }, 2000)
  
  websocket.on('message', function(message) {
    messages.push({message:message, origin:request.headers.origin})
    websocket.send(JSON.stringify(messages));
  })

  websocket.on('close', function() {
    clearInterval(intervalHandler);
  })
})