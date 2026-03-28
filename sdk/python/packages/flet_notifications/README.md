# flet_notifications
LocalNotifications control for Flet. Based on [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)


<div align="center">
  <table>
    <tr>
      <td width="50%">
        <video width="100%" src="https://github.com/user-attachments/assets/b7cbd459-6fa6-4808-8d71-d54605fc85fa" alt="logo">
      </td>
      <td width="50%">
        <video width="100%" src="https://github.com/user-attachments/assets/c9750064-c282-409f-a819-c884c62c3329" >
      </td>
    </tr>
  </table>
</div>

### Usage
#### Initialization
```python
# import the control
from flet_notifications import LocalNotifications
# initialize it
notifications = LocalNotifications()
# add it to the page overlay (since it's non visual)
page.overlay.append(notifications)
```

#### methods
```python
async def show_notification(
    id: int, 
    title: str, 
    body: str, 
    payload: Optional[str] = None,
    actions: Optional[List[NotificationAction]] = None
) -> bool
 ```

Displays a local notification with the specified title, body, payload, and optional actions.

Parameters:

- id ( int ): Unique identifier for the notification.
- title ( str ): Title of the notification.
- body ( str ): Body content of the notification.
- payload ( Optional[str] ): Optional payload that can be used when the notification is tapped.
- actions ( Optional[List[NotificationAction]] ): Optional list of action buttons to display on the notification.
Returns:

- bool : True if the notification was successfully shown, False otherwise.


```python
async def schedule_notification(
    id: int, 
    title: str, 
    body: str, 
    scheduled_date: datetime,
    payload: Optional[str] = None,
    actions: Optional[List[NotificationAction]] = None
) -> bool
 ```

Schedules a local notification to be displayed at a specific date and time.

Parameters:

- id ( int ): Unique identifier for the notification.
- title ( str ): Title of the notification.
- body ( str ): Body content of the notification.
- scheduled_date ( datetime ): Date and time when the notification should be displayed.
- payload ( Optional[str] ): Optional payload that can be used when the notification is tapped.
- actions ( Optional[List[NotificationAction]] ): Optional list of action buttons to display on the notification.
Returns:

- bool : True if the notification was successfully scheduled, False otherwise.


```python
async def request_permissions() -> bool
```

Requests permissions for displaying notifications.

Returns:

- bool : True if permissions were granted, False otherwise.

### Notification Actions

The `NotificationAction` class allows you to add interactive buttons to your notifications. Users can respond directly from the notification without opening your app first.

```python
from flet_notifications import NotificationAction

# Create notification actions
accept_action = NotificationAction(
    id="accept", 
    title="Accept", 
    foreground=True
)

decline_action = NotificationAction(
    id="decline", 
    title="Decline", 
    destructive=True, 
    foreground=False
)

# Show notification with actions
await notifications.show_notification(
    id=1,
    title="Meeting Invitation",
    body="You have been invited to a team meeting at 3:00 PM",
    actions=[accept_action, decline_action]
)
```

#### NotificationAction Parameters

```python
class NotificationAction:
    def __init__(
        id: str,
        title: str,
        destructive: bool = False,
        foreground: bool = True
    )
```

- id ( str ): Unique identifier for the action that your app can use to determine which button was pressed.
- title ( str ): The text displayed on the action button.
- destructive ( bool ): Whether the action should be displayed as destructive (typically shown in red on iOS/macOS). Default is False.
- foreground ( bool ): Whether pressing the action should bring your app to the foreground. Default is True.

#### Handling Action Responses

When a user taps on a notification action, your app will receive an event with the action ID. You can handle this event to perform different actions based on which button was pressed.

Example:

```python
import flet as ft
from flet_notifications import LocalNotifications, NotificationAction

async def main(page: ft.Page):
    # Initialize notifications
    notifications = LocalNotifications()
    page.overlay.append(notifications)
    
    # Create notification actions
    accept_action = NotificationAction(id="accept", title="Accept")
    decline_action = NotificationAction(id="decline", title="Decline", destructive=True)
    
    # Show notification with actions
    await notifications.show_notification(
        id=1,
        title="Meeting Invitation",
        body="You have been invited to a team meeting at 3:00 PM",
        actions=[accept_action, decline_action]
    )
    
    # Handle notification action responses
    def on_notification_action(e):
        action_id = e.data["actionId"]
        if action_id == "accept":
            page.snack_bar = ft.SnackBar(content=ft.Text("Meeting accepted!"))
            page.snack_bar.open = True
        elif action_id == "decline":
            page.snack_bar = ft.SnackBar(content=ft.Text("Meeting declined!"))
            page.snack_bar.open = True
        page.update()
    
    # Subscribe to notification action events
    notifications.on_notification_action = on_notification_action

ft.app(main)
```

Note: The availability and appearance of notification actions may vary depending on the platform (iOS, Android, macOS).
```

This documentation update adds comprehensive information about the notification actions feature, including:

1. Updated method signatures to include the `actions` parameter
2. A new section dedicated to notification actions
3. Details about the `NotificationAction` class and its parameters
4. An example of how to create and use notification actions
5. Information about handling action responses