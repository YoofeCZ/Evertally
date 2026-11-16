//! Windows notifications for updates: one notification per download that shows its progress and then the result.
//!
//! Windows shows notifications only for an app it knows: the installer gives the Start menu shortcut the identity
//! [`APP_ID`] (`installer/Evertally.iss`). Without it (a portable copy, another OS) every call quietly does nothing:
//! the tray status still tells the same.
#[cfg(windows)]
pub const APP_ID: &str = "AFStudio.Evertally";

/// One running update notification (download progress, then the result).
pub struct Progress {
    #[cfg(windows)]
    tag: String,
    #[cfg(windows)]
    sequence: u32,
    #[cfg(windows)]
    shown: bool,
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// The notification text: a title, a line, and a progress bar bound to values that change while it shows.
#[must_use]
pub fn progress_xml(title: &str) -> String {
    format!(
        r#"<toast><visual><binding template="ToastGeneric"><text>Evertally</text><text>{}</text><progress value="{{progressValue}}" valueStringOverride="{{progressText}}" status="{{progressStatus}}"/></binding></visual></toast>"#,
        escape(title)
    )
}

#[must_use]
pub fn message_xml(title: &str, body: &str) -> String {
    format!(r#"<toast><visual><binding template="ToastGeneric"><text>{}</text><text>{}</text></binding></visual></toast>"#, escape(title), escape(body))
}

#[cfg(windows)]
mod win {
    use windows::Data::Xml::Dom::XmlDocument;
    use windows::UI::Notifications::{NotificationData, ToastNotification, ToastNotificationManager};
    use windows::core::{HSTRING, Result};

    fn toast(xml: &str) -> Result<ToastNotification> {
        let doc = XmlDocument::new()?;
        doc.LoadXml(&HSTRING::from(xml))?;
        ToastNotification::CreateToastNotification(&doc)
    }
    fn data(values: &[(&str, &str)], sequence: u32) -> Result<NotificationData> {
        let data = NotificationData::new()?;
        let map = data.Values()?;
        for (k, v) in values {
            map.Insert(&HSTRING::from(*k), &HSTRING::from(*v))?;
        }
        data.SetSequenceNumber(sequence)?;
        Ok(data)
    }
    pub fn show(xml: &str, tag: Option<&str>, values: &[(&str, &str)]) -> Result<()> {
        let notification = toast(xml)?;
        if let Some(tag) = tag {
            notification.SetTag(&HSTRING::from(tag))?;
            notification.SetGroup(&HSTRING::from("evertally"))?;
            notification.SetData(&data(values, 1)?)?;
        }
        ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(super::APP_ID))?.Show(&notification)
    }
    pub fn update(tag: &str, values: &[(&str, &str)], sequence: u32) -> Result<()> {
        ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(super::APP_ID))?
            .UpdateWithTagAndGroup(&data(values, sequence)?, &HSTRING::from(tag), &HSTRING::from("evertally"))
            .map(|_| ())
    }
}

impl Progress {
    /// Shows "title" with an empty bar and `status` under it.
    #[must_use]
    pub fn start(tag: &str, title: &str, status: &str) -> Self {
        #[cfg(windows)]
        {
            let shown = win::show(&progress_xml(title), Some(tag), &[("progressValue", "0"), ("progressText", ""), ("progressStatus", status)]).is_ok();
            Self { tag: tag.to_owned(), sequence: 1, shown }
        }
        #[cfg(not(windows))]
        {
            let _ = (tag, title, status);
            Self {}
        }
    }

    /// Moves the bar: `done` of `total` bytes, with `status` under it.
    pub fn set(&mut self, done: u64, total: u64, status: &str) {
        #[cfg(windows)]
        if self.shown {
            let fraction = if total == 0 { 0.0 } else { (done as f64 / total as f64).clamp(0.0, 1.0) };
            self.sequence += 1;
            let percent = format!("{} %", (fraction * 100.0).round() as u64);
            let _ = win::update(&self.tag, &[("progressValue", &format!("{fraction:.3}")), ("progressText", &percent), ("progressStatus", status)], self.sequence);
        }
        #[cfg(not(windows))]
        let _ = (done, total, status);
    }
}

/// A plain notification (the result of an update).
pub fn message(title: &str, body: &str) {
    #[cfg(windows)]
    let _ = win::show(&message_xml(title, body), None, &[]);
    #[cfg(not(windows))]
    let _ = (title, body);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notification_text_is_escaped_and_binds_the_progress_values() {
        let xml = progress_xml("Evertally <0.9.52> & co");
        assert!(xml.contains("Evertally &lt;0.9.52&gt; &amp; co"));
        assert!(xml.contains(r#"value="{progressValue}""#) && xml.contains(r#"status="{progressStatus}""#));
        assert!(message_xml("a\"b", "c").contains("a&quot;b"));
    }
}
