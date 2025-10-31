const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');
const { spawn } = require('child_process');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(express.static(path.join(__dirname, 'public')));

let objectCounts = {};
let fieldObjects = {}

setInterval(simulationStep, 50);

let simulationState = "Stopped"

function simulationStep(){

  if(simulationState != "Started") return;

  let keys = Object.keys(fieldObjects);

  for(var i = 0; i < keys.length; i++){

    //console.log(keys[i]);

    if(keys[i].startsWith("drone")){

      let obj = fieldObjects[keys[i]];
      let targetObj = fieldObjects[obj.objectData.fireTarget];

      if(targetObj != undefined){

        let currentPos = obj.objectCoord; //[x,y]
        let targetPos = [...targetObj.objectCoord]; //[x2,y2]
        //targetPos[0] += 0;
        //targetPos[1] += 0;

        //console.log("CURRENT", currentPos, "TARGET", targetPos);
        //targetPos = calcTargetPos(currentPos, targetPos, 80);

        //console.log("UPDATED TARGET", targetPos);

        let dist = Math.sqrt((currentPos[0] - targetPos[0])**2 + (currentPos[1] - targetPos[1])**2);

        if(dist > 110){
          currentPos = moveToPos(currentPos, targetPos, 4);

          //console.log("UPDATED CURRENT", currentPos);
          currentPos[0] = Math.floor(currentPos[0] * 1000) / 1000;
          currentPos[1] = Math.floor(currentPos[1] * 1000) / 1000;

          obj.objectCoord = currentPos;
        }



      }

    }

  }

}

function calcTargetPos(currentPos, targetPos, dist){
  const vectorX = currentPos[0] - targetPos[0];
  const vectorY = currentPos[1] - targetPos[1];

  const magnitude = Math.sqrt(vectorX * vectorX + vectorY * vectorY);

  const unitVectorX = vectorX / magnitude;
  const unitVectorY = vectorY / magnitude;

  const newTargetPosX = targetPos[0] + unitVectorX * dist;
  const newTargetPosY = targetPos[1] + unitVectorY * dist;

  return [newTargetPosX, newTargetPosY];
}
function moveToPos(currentPos, targetPos, distance){

  const vectorX = targetPos[0] - currentPos[0];
  const vectorY = targetPos[1] - currentPos[1];


  const magnitude = Math.sqrt(vectorX * vectorX + vectorY * vectorY);

  if (magnitude <= distance) {
    return targetPos;
  }

  const unitVectorX = vectorX / magnitude;
  const unitVectorY = vectorY / magnitude;

  const newPosX = currentPos[0] + unitVectorX * distance;
  const newPosY = currentPos[1] + unitVectorY * distance;

  return [newPosX, newPosY];
}

wss.on('connection', ws => {
    console.log('Client connected');

    let messageData = {};
    messageData.event = "fieldObjects";
    messageData.objects = fieldObjects;

    ws.send(JSON.stringify(messageData));
    ws.send(JSON.stringify({event: "simulationState", state: simulationState}));

    ws.on('message', message => {
        //console.log(`Received: ${message}`);

        let data = JSON.parse(message);

        if(data.event == "addObject"){

          let object = {};

          object.objectType = data.objectType
          objectCounts[data.objectType] = (objectCounts[data.objectType] || 0) + 1;

          object.objectID = data.objectType + objectCounts[data.objectType]
          object.objectCoord = data.objectCoord
          object.objectData = data.objectData;

          fieldObjects[object.objectID] = object;

          let messageData = {};
          messageData.event = "fieldObjects";
          messageData.objects = fieldObjects;

          ws.send(JSON.stringify(messageData));
          ws.send(JSON.stringify({event: "simulationState", state: simulationState}));

        }
        if(data.event == "requestObjects"){

          let messageData = {};
          messageData.event = "fieldObjects";
          messageData.objects = fieldObjects;

          ws.send(JSON.stringify(messageData));
          ws.send(JSON.stringify({event: "simulationState", state: simulationState}));
        }
        if(data.event == "removeObject"){

          let toRemove = data.objectID;
          delete fieldObjects[toRemove];

          let keys = Object.keys(fieldObjects);

          for(var i = 0; i < keys.length; i++){
            if(keys[i].startsWith("drone")){
              let obj = fieldObjects[keys[i]];
              if(obj.objectData.fireTarget == toRemove){
                obj.objectData.fireTarget = "none";
              }
            }
          }

          let messageData = {};
          messageData.event = "fieldObjects";
          messageData.objects = fieldObjects;

          ws.send(JSON.stringify(messageData));
          ws.send(JSON.stringify({event: "simulationState", state: simulationState}));


        }
        if(data.event == "simulationState"){

          if(data.state == "Reasoning"){


            let droneArrString = [];
            let fireArrString = [];
            let objectArrString = [];

            let keys = Object.keys(fieldObjects);

            for(var i = 0; i < keys.length; i++){

              if(keys[i].startsWith("drone")){
                let obj = {droneID: keys[i], position: fieldObjects[keys[i]].objectCoord}
                droneArrString.push(obj);
              }
              else if(keys[i].startsWith("fire")){
                let obj = {fireID: keys[i], position: fieldObjects[keys[i]].objectCoord}
                fireArrString.push(obj);
              }
              else{
                let obj = {objectID: keys[i], position: fieldObjects[keys[i]].objectCoord}
                objectArrString.push(obj);
              }

            }

            droneArrString = JSON.stringify(droneArrString);
            fireArrString = JSON.stringify(fireArrString);
            objectArrString = JSON.stringify(objectArrString)

            const prompt = `"Position of drones: ${droneArrString}. Position of fires: ${fireArrString}. Position of objects: ${objectArrString}. Each object has width / height of 100 units. Coordinate represents top left corner. Redirect each and every drone to target the fires, maximizing safety and survivors. Output in the exact format (Example): JJJ [ { droneID: drone69, targetFire: fire32 }, { droneID: drone42, targetFire: fire47 }, ...all drones ] JJJ. Start and end your JSON output with the following characters: JJJ. Be sure JSON is valid with double quotes. Prioritize certain fires based on surroundings such as homes. The more homes within about 100 units near a fire, the more drones should be sent to it. A home 100 units from a fire is about the same danger as a home 5 units from a fire. You are not allowed to use external tools, only your reasoning is allowed. State your reasoning and THINK before outputting the JSON."`;

            console.log("SEND IN THE PROMPT: ", prompt);

            simulationState = "Reasoning"
            ws.send(JSON.stringify({event: "simulationState", state: simulationState}));

            const geminiProcess = spawn('gemini', [
                '--output-format',
                'stream-json',
                /*
        				'--model',
        				'gemini-2.5-flash',
                */
                '--allowed-tools',
                '[]',
                prompt
            ], {shell: true});

            let buffer = '';

            geminiProcess.stdout.on('data', (data) => {


                let json = JSON.parse(data.toString());

                if("role" in json && json["role"] == "assistant"){
                  buffer += json["content"];
                }

                let dataObj = {event: "reasoning", reasoning: json};

                console.log(`Data: ${data.toString()}`);

                if(json.type == "init"){
                  ws.send(JSON.stringify(dataObj));
                }

                //console.log(data);
                //ws.send(JSON.stringify(dataObj));

            });


            geminiProcess.stderr.on('data', (data) => {
                console.error(`Error: ${data}`);
            });

            geminiProcess.on('close', (code) => {

                console.log("Finished");
                console.log(buffer);
                console.log(buffer.split("JJJ")[1])

                let ans = JSON.parse(buffer.split("JJJ")[1]);

                for(var i = 0; i < ans.length; i++){

                  let obj = ans[i];
                  //console.log(obj);
                  fieldObjects[obj["droneID"]].objectData.fireTarget = obj["targetFire"];

                }

                simulationState = "Started";
                ws.send(JSON.stringify({event: "simulationState", state: simulationState}));
                ws.send(JSON.stringify({event: "reasoning",
                  reasoning: {
                    type: "message",
                    role: "assistant",
                    content: buffer
                  }
                }));

            });

          }
          if(data.state == "Stopped"){
            simulationState = "Stopped";
          }

        }

    });

    ws.on('close', () => {
        console.log('Client disconnected');
    });

    ws.on('error', error => {
        console.error('WebSocket error:', error);
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
    console.log(`Open http://localhost:${PORT} in your browser`);
});
