import json
from typing import Any, Dict, List, Optional
from datetime import datetime
from flet.core.control import Control

class NotificationAction:
   """
   Represents an action button in a notification.
   """
   def __init__(
       self,
       id: str,
       title: str,
       destructive: bool = False,
       foreground: bool = True
   ):
       """
       Initialize a notification action.
       
       Args:
           id: Unique identifier for the action
           title: Display text for the action button
           destructive: Whether the action is destructive (e.g. delete)
           foreground: Whether tapping the action should bring the app to the foreground
       """
       self.id = id
       self.title = title
       self.destructive = destructive
       self.foreground = foreground
   
   def __str__(self) -> str:
       """String representation for passing to the Dart side."""
       return f"{self.id}|{self.title}|{str(self.destructive).lower()}|{str(self.foreground).lower()}"

class LocalNotifications(Control):
    """
    A Flet control for managing local notifications.
    
    This control integrates the flutter_local_notifications package and provides
    a Python interface for sending local notifications from a Flet app.
    """

    def __init__(
        self,
        tooltip: Optional[str] = None,
        visible: Optional[bool] = None,
        data: Any = None,
        on_notification_action: Optional[callable] = None,
    ):
        Control.__init__(
            self,
            tooltip=tooltip,
            visible=visible,
            data=data,
        )
        
        self.on_notification_action = on_notification_action

    def _get_control_name(self):
        return "flet_notifications"
   
    def build(self):
        self._add_event_handler("notification_action", self._notification_action_handler)
        super().build()
   
    async def _notification_action_handler(self, e):
        if self.on_notification_action is not None:
            try:
                # The event data might be directly available or nested
                if hasattr(e, 'data') and e.data:
                    if isinstance(e.data, str):
                        action_data = json.loads(e.data)
                        action_id = action_data.get("actionId", "unknown")
                        payload = action_data.get("payload", "")
                    else:
                        # If data is already parsed
                        action_id = e.data.get("actionId", "unknown")
                        payload = e.data.get("payload", "")
                else:
                    # Fallback to using the event object directly
                    action_id = getattr(e, "actionId", "unknown")
                    payload = getattr(e, "payload", "")
                
                # Call the user's callback with the action ID and payload
                await self.on_notification_action(action_id, payload)
            except Exception as ex:
                print(f"Error handling notification action: {ex}")

    async def show_notification(
       self, 
       id: int, 
       title: str, 
       body: str, 
       payload: Optional[str] = None,
       actions: Optional[List[NotificationAction]] = None
   ) -> bool:
       """
       Show a notification with optional interactive action buttons.
       
       Args:
           id: Unique identifier for the notification
           title: Title of the notification
           body: Body text of the notification
           payload: Optional data to associate with the notification
           actions: Optional list of NotificationAction objects to display as buttons
           
       Returns:
           True if the notification was sent successfully, False otherwise
       """
       args = {
           "id": str(id),
           "title": title,
           "body": body,
       }
       
       if payload:
           args["payload"] = payload
           
       if actions:
           args["actions"] = ",".join(str(action) for action in actions)
       
       result = await self.invoke_method_async("show_notification", args)
       return result == "ok"
   
    async def schedule_notification(
       self, 
       id: int, 
       title: str, 
       body: str, 
       scheduled_date: datetime,
       payload: Optional[str] = None,
       actions: Optional[List[NotificationAction]] = None
   ) -> bool:
       """
       Schedule a notification for a future time with optional action buttons.
       
       Args:
           id: Unique identifier for the notification
           title: Title of the notification
           body: Body text of the notification
           scheduled_date: The date and time to show the notification
           payload: Optional data to associate with the notification
           actions: Optional list of NotificationAction objects to display as buttons
           
       Returns:
           True if the notification was scheduled successfully, False otherwise
       """
       args = {
           "id": str(id),
           "title": title,
           "body": body,
           "scheduled_date": scheduled_date.isoformat(),
       }
       
       if payload:
           args["payload"] = payload
           
       if actions:
           args["actions"] = ",".join(str(action) for action in actions)
       
       result = await self.invoke_method_async("schedule_notification", args)
       return result == "ok"
   
    async def request_permissions(self) -> bool:
       """
       Request notification permissions from the user.
       
       Returns:
           True if permissions were granted, False otherwise
       """
       result = await self.invoke_method_async("request_permissions", {})
       return result.lower() == "true"