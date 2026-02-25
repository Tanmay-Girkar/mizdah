```json
{
  "openapi": "3.0.0",
  "info": {
    "title": "Mizdah Full API Reference",
    "version": "1.0.0",
    "description": "API specifications for the Mizdah video conferencing mobile app."
  },
  "servers": [
    {
      "url": "http://192.168.1.24:3000",
      "description": "Local Development Gateway"
    }
  ],
  "components": {
    "securitySchemes": {
      "BearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT"
      }
    }
  },
  "paths": {
    "/api/auth/signup": {
      "post": {
        "summary": "Sign Up",
        "tags": [
          "Auth"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "email": {
                    "type": "string",
                    "example": "user@example.com"
                  },
                  "password": {
                    "type": "string",
                    "example": "mypassword"
                  },
                  "name": {
                    "type": "string",
                    "example": "John Doe"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/auth/login": {
      "post": {
        "summary": "Login",
        "tags": [
          "Auth"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "email": {
                    "type": "string",
                    "example": "user@example.com"
                  },
                  "password": {
                    "type": "string",
                    "example": "mypassword"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/auth/me": {
      "get": {
        "summary": "Get Current User",
        "tags": [
          "Auth"
        ],
        "security": [
          {
            "BearerAuth": []
          }
        ],
        "parameters": [],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/auth/update": {
      "post": {
        "summary": "Update Profile",
        "tags": [
          "Auth"
        ],
        "security": [
          {
            "BearerAuth": []
          }
        ],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "name": {
                    "type": "string",
                    "example": "New Name"
                  },
                  "password": {
                    "type": "string",
                    "example": "newpassword"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meetings/create": {
      "post": {
        "summary": "Create Meeting",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "hostId": {
                    "type": "string",
                    "example": "uuid-1234"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meeting/{code}": {
      "get": {
        "summary": "Get Meeting Info",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [
          {
            "name": "code",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Meeting code"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meetings/user/{userId}": {
      "get": {
        "summary": "Get Meetings by Host",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [
          {
            "name": "userId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "User ID"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meeting/{code}/settings": {
      "patch": {
        "summary": "Update Meeting Settings",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [
          {
            "name": "code",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Meeting code"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "private_chat_enabled": {
                    "type": "boolean",
                    "example": false
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meeting/settings": {
      "get": {
        "summary": "Get Global System Settings",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      },
      "post": {
        "summary": "Update Global System Settings",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "max_participants": {
                    "type": "integer",
                    "example": 50
                  },
                  "meeting_time_limit": {
                    "type": "integer",
                    "example": 45
                  },
                  "allow_recordings": {
                    "type": "boolean",
                    "example": false
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meeting/feedback": {
      "post": {
        "summary": "Submit Feedback",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "category": {
                    "type": "string",
                    "example": "Audio Quality"
                  },
                  "description": {
                    "type": "string",
                    "example": "Echo during the call"
                  },
                  "user_email": {
                    "type": "string",
                    "example": "user@example.com"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meeting/contact": {
      "post": {
        "summary": "Contact / Support Form",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "first_name": {
                    "type": "string",
                    "example": "John"
                  },
                  "last_name": {
                    "type": "string",
                    "example": "Doe"
                  },
                  "email": {
                    "type": "string",
                    "example": "john@example.com"
                  },
                  "message": {
                    "type": "string",
                    "example": "Help me"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/meeting/report-abuse": {
      "post": {
        "summary": "Report Abuse",
        "tags": [
          "Meeting"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "abuse_type": {
                    "type": "string",
                    "example": "Harassment"
                  },
                  "abuser_names": {
                    "type": "string",
                    "example": "John Doe"
                  },
                  "description": {
                    "type": "string",
                    "example": "Offensive language"
                  },
                  "meeting_id": {
                    "type": "string",
                    "example": "abc-xyz"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/participant/join": {
      "post": {
        "summary": "Log Participant Join",
        "tags": [
          "Participant"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "meetingId": {
                    "type": "string",
                    "example": "abc"
                  },
                  "userId": {
                    "type": "string",
                    "example": "uuid-123"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/participant/leave": {
      "post": {
        "summary": "Log Participant Leave",
        "tags": [
          "Participant"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "meetingId": {
                    "type": "string",
                    "example": "abc"
                  },
                  "userId": {
                    "type": "string",
                    "example": "uuid-123"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/participant/user/{userId}": {
      "get": {
        "summary": "Get Users Meeting History",
        "tags": [
          "Participant"
        ],
        "security": [],
        "parameters": [
          {
            "name": "userId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "userId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/participant/{meetingId}": {
      "get": {
        "summary": "Get Participants in a Meeting",
        "tags": [
          "Participant"
        ],
        "security": [],
        "parameters": [
          {
            "name": "meetingId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "meetingId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/chat/send": {
      "post": {
        "summary": "Send Message (Public)",
        "tags": [
          "Chat"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "meetingId": {
                    "type": "string",
                    "example": "abc"
                  },
                  "senderId": {
                    "type": "string",
                    "example": "uuid-123"
                  },
                  "senderName": {
                    "type": "string",
                    "example": "John"
                  },
                  "content": {
                    "type": "string",
                    "example": "Hello!"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/chat/{meetingId}": {
      "get": {
        "summary": "Get Messages",
        "tags": [
          "Chat"
        ],
        "security": [],
        "parameters": [
          {
            "name": "meetingId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "meetingId"
          },
          {
            "name": "userId",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            },
            "description": "userId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/chat/{messageId}": {
      "delete": {
        "summary": "Delete Message",
        "tags": [
          "Chat"
        ],
        "security": [],
        "parameters": [
          {
            "name": "messageId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "messageId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/notifications/invite": {
      "post": {
        "summary": "Send Meeting Invite",
        "tags": [
          "Notifications"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "userId": {
                    "type": "string",
                    "example": "uuid-123"
                  },
                  "meetingCode": {
                    "type": "string",
                    "example": "abc"
                  },
                  "message": {
                    "type": "string",
                    "example": "Join!"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/notifications/reminder": {
      "post": {
        "summary": "Send Meeting Reminder",
        "tags": [
          "Notifications"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "userId": {
                    "type": "string",
                    "example": "uuid-123"
                  },
                  "scheduleId": {
                    "type": "string",
                    "example": "sch-123"
                  },
                  "message": {
                    "type": "string",
                    "example": "Starts soon"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/notifications/user/{userId}": {
      "get": {
        "summary": "Get User Notifications",
        "tags": [
          "Notifications"
        ],
        "security": [],
        "parameters": [
          {
            "name": "userId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "userId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/scheduling/schedule": {
      "post": {
        "summary": "Create Schedule",
        "tags": [
          "Scheduling"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "hostId": {
                    "type": "string",
                    "example": "uuid-123"
                  },
                  "title": {
                    "type": "string",
                    "example": "Standup"
                  },
                  "startTime": {
                    "type": "string",
                    "example": "2026-02-25T09:00:00Z"
                  },
                  "endTime": {
                    "type": "string",
                    "example": "2026-02-25T09:30:00Z"
                  },
                  "recurrence": {
                    "type": "string",
                    "example": "weekly"
                  },
                  "timezone": {
                    "type": "string",
                    "example": "UTC"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/scheduling/user/{userId}": {
      "get": {
        "summary": "Get Users Scheduled Meetings",
        "tags": [
          "Scheduling"
        ],
        "security": [],
        "parameters": [
          {
            "name": "userId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "userId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/scheduling/{scheduleId}": {
      "delete": {
        "summary": "Delete Schedule",
        "tags": [
          "Scheduling"
        ],
        "security": [],
        "parameters": [
          {
            "name": "scheduleId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "scheduleId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/recording/start/{meetingId}": {
      "post": {
        "summary": "Start Recording",
        "tags": [
          "Recording"
        ],
        "security": [],
        "parameters": [
          {
            "name": "meetingId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "meetingId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/recording/stop/{meetingId}": {
      "post": {
        "summary": "Stop Recording",
        "tags": [
          "Recording"
        ],
        "security": [],
        "parameters": [
          {
            "name": "meetingId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "meetingId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/recording/{meetingId}": {
      "get": {
        "summary": "Get Recordings for a Meeting",
        "tags": [
          "Recording"
        ],
        "security": [],
        "parameters": [
          {
            "name": "meetingId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "meetingId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/recording/": {
      "get": {
        "summary": "Get All Recordings",
        "tags": [
          "Recording"
        ],
        "security": [],
        "parameters": [],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/files/{fileId}": {
      "get": {
        "summary": "Get File",
        "tags": [
          "File"
        ],
        "security": [],
        "parameters": [
          {
            "name": "fileId",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "fileId"
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    },
    "/api/history/store": {
      "post": {
        "summary": "Store Call History",
        "tags": [
          "History"
        ],
        "security": [],
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "meetingId": {
                    "type": "string",
                    "example": "abc"
                  },
                  "duration": {
                    "type": "integer",
                    "example": 1800
                  },
                  "endedAt": {
                    "type": "string",
                    "example": "2026-02-24T11:30:00Z"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response"
          }
        }
      }
    }
  }
}
```
