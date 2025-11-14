# Fire Warden

[![Build Status](https://github.com/fireforce6-f25/fire-warden/actions/workflows/ci.yml/badge.svg)](https://github.com/fireforce6-f25/fire-warden/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/fireforce6-f25/fire-warden?label=Release)](https://github.com/fireforce6-f25/fire-warden/releases/latest)


<img width="1908" height="896" alt="image" src="https://github.com/user-attachments/assets/ae715753-2bec-43f8-9466-065930ade121" />


# Fire Warden Simulation API

This document provides instructions for developers on how to interact with the Fire Warden Simulation WebSocket API. This real-time, interactive simulation allows for the dynamic addition and removal of objects on a field, management of AI goals, and monitoring of an AI warden's reasoning process.

## Getting Started

To connect to the simulation, you will need a WebSocket client. The server runs locally and is accessible at the following URI:

`ws://localhost:3000`

Once connected, you can begin sending and receiving JSON-formatted messages to interact with the simulation.

## API Reference

Communication with the server is handled through a series of events. Each event is a JSON object with a specific structure.

### Client-Sent Events

These are messages that your client will send to the server to perform actions within the simulation.

#### **`requestObjects`**
Requests the current state of all objects on the field. The server will respond with a `fieldObjects` event.

**Example:**
```json
{
  "event": "requestObjects"
}```

#### **`addObject`**
Adds a new object to the simulation field.

**Properties:**
*   `event`: `"addObject"`
*   `objectType`: The type of object to add. Can be `"fire"`, `"drone"`, `"house"`, or `"person"`.
*   `objectCoord`: An array containing the X and Y coordinates `[x, y]` for the object's position.
*   `objectData`: An object containing data specific to the object type.
    *   For `fire`: `{ "size": 1 }`
    *   For `drone`: `{ "fireTarget": "none" }`

**Example:**
```json
{
  "event": "addObject",
  "objectType": "drone",
  "objectCoord": [150, 200],
  "objectData": {
    "fireTarget": "none"
  }
}
```

#### **`removeObject`**
Removes an object from the simulation field.

**Properties:**
*   `event`: `"removeObject"`
*   `objectID`: The unique identifier of the object to be removed.

**Example:**
```json
{
  "event": "removeObject",
  "objectID": "someUniqueId"
}
```

#### **`simulationState`**
Changes the state of the simulation.

**Properties:**
*   `event`: `"simulationState"`
*   `state`: The desired new state. Can be `"Reasoning"`, `"Started"`, or `"Stopped"`.

**Example:**```json
{
  "event": "simulationState",
  "state": "Reasoning"
}```

#### **`addGoal`**
Adds a new goal for the AI Warden.

**Properties:**
*   `event`: `"addGoal"`
*   `goal`: A string describing the goal.

**Example:**
```json
{
  "event": "addGoal",
  "goal": "Protect all houses from fire."
}
```

#### **`removeGoal`**
Removes a goal from the AI Warden's list of objectives.

**Properties:**
*   `event`: `"removeGoal"`
*   `index`: The numerical index of the goal to be removed.

**Example:**
```json
{
  "event": "removeGoal",
  "index": 0
}
```

#### **`requestGoals`**
Requests the current list of goals for the AI Warden. The server will respond with a `goals` event.

**Example:**
```json
{
  "event": "requestGoals"
}
```

### Server-Sent Events

These are messages that your client will receive from the server.

#### **`fieldObjects`**
Provides the current state of all objects on the simulation field. This is sent in response to a `requestObjects` event and periodically to keep clients updated.

**Payload:**
An object where each key is an `objectID` and the value is an object containing the object's data.

**Example Payload:**
```json
{
  "event": "fieldObjects",
  "objects": {
    "fire1": {
      "objectID": "fire1",
      "objectType": "fire",
      "objectCoord": [100, 100],
      "objectData": { "size": 1 }
    },
    "drone1": {
      "objectID": "drone1",
      "objectType": "drone",
      "objectCoord": [150, 200],
      "objectData": { "fireTarget": "fire1" }
    }
  }
}
```

#### **`simulationState`**
Notifies clients of a change in the simulation's state.

**Payload:**
*   `event`: `"simulationState"`
*   `state`: The new state of the simulation (`"Reasoning"`, `"Started"`, or `"Stopped"`).

**Example Payload:**
```json
{
  "event": "simulationState",
  "state": "Started"
}
```

#### **`reasoning`**
Provides insight into the AI Warden's decision-making process.

**Payload:**
*   `event`: `"reasoning"`
*   `reasoning`: An object containing the reasoning data.
    *   `type`: The type of reasoning message (`"init"` or `"message"`).
    *   `role`: The role of the message source (e.g., `"assistant"`).
    *   `content`: The reasoning text.

**Example Payload:**
```json
{
  "event": "reasoning",
  "reasoning": {
    "type": "message",
    "role": "assistant",
    "content": "The nearest drone is being dispatched to the new fire."
  }
}
```

#### **`goals`**
Provides the current list of the AI Warden's goals. This is sent in response to a `requestGoals` event.

**Payload:**
*   `event`: `"goals"`
*   `goals`: An array of strings, where each string is a goal.

**Example Payload:**
```json
{
  "event": "goals",
  "goals": [
    "Protect all houses from fire.",
    "Ensure all people are safe."
  ]
}
```
