/* libnotify.vapi generated by lt-vapigen, do not modify. */

[CCode (cprefix = "Notify", lower_case_cprefix = "notify_")]
namespace Notify {
	[CCode (cheader_filename = "libnotify/notify.h")]
	public class Notification : GLib.Object {
		public void add_action (string action, string label, Notify.ActionCallback# callback);
		public void attach_to_status_icon (Gtk.StatusIcon status_icon);
		public void attach_to_widget (Gtk.Widget attach);
		public void clear_actions ();
		public void clear_hints ();
		public bool close () throws GLib.Error;
		[CCode (has_construct_function = false)]
		public Notification (string summary, string body, string icon, Gtk.Widget attach);
		public void set_category (string category);
		public void set_geometry_hints (Gdk.Screen screen, int x, int y);
		public void set_hint_byte (string key, uchar value);
		public void set_hint_byte_array (string key, uchar[] value, size_t len);
		public void set_hint_double (string key, double value);
		public void set_hint_int32 (string key, int value);
		public void set_hint_string (string key, string value);
		public void set_icon_from_pixbuf (Gdk.Pixbuf icon);
		public void set_timeout (int timeout);
		public void set_urgency (Notify.Urgency urgency);
		public bool show () throws GLib.Error;
		public bool update (string summary, string body, string icon);
		[CCode (has_construct_function = false)]
		public Notification.with_status_icon (string summary, string body, string icon, Gtk.StatusIcon status_icon);
		[NoAccessorMethod]
		public Gtk.Widget attach_widget { get; set construct; }
		[NoAccessorMethod]
		public string body { get; set construct; }
		[NoAccessorMethod]
		public string icon_name { get; set construct; }
		[NoAccessorMethod]
		public Gtk.StatusIcon status_icon { get; set construct; }
		[NoAccessorMethod]
		public string summary { get; set construct; }
		public virtual signal void closed ();
	}
	[CCode (cprefix = "NOTIFY_URGENCY_", has_type_id = "0", cheader_filename = "libnotify/notify.h")]
	public enum Urgency {
		LOW,
		NORMAL,
		CRITICAL
	}
	[CCode (cheader_filename = "libnotify/notify.h")]
	public delegate void ActionCallback (Notify.Notification p1, string p2);
	[CCode (cheader_filename = "libnotify/notify.h")]
	public const int EXPIRES_DEFAULT;
	[CCode (cheader_filename = "libnotify/notify.h")]
	public const int EXPIRES_NEVER;
	[CCode (cheader_filename = "libnotify/notify.h")]
	public static weak string get_app_name ();
	[CCode (cheader_filename = "libnotify/notify.h")]
	public static weak GLib.List get_server_caps ();
	[CCode (cheader_filename = "libnotify/notify.h")]
	public static bool get_server_info (out weak string ret_name, out weak string ret_vendor, out weak string ret_version, out weak string ret_spec_version);
	[CCode (cheader_filename = "libnotify/notify.h")]
	public static bool init (string app_name);
	[CCode (cheader_filename = "libnotify/notify.h")]
	public static bool is_initted ();
	[CCode (cheader_filename = "libnotify/notify.h")]
	public static void uninit ();
}
