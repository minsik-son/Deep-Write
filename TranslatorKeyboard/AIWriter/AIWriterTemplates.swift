import Foundation

struct AIWriterTemplate {
    let id: String
    let emoji: String
    let nameKey: String
    let promptKey: String
    let suggestedTone: String
}

let aiWriterTemplates: [AIWriterTemplate] = [
    AIWriterTemplate(id: "job_reply", emoji: "\u{1F4BC}", nameKey: "template.job_reply", promptKey: "template.job_reply.prompt", suggestedTone: "professional"),
    AIWriterTemplate(id: "meeting_reschedule", emoji: "\u{1F4C5}", nameKey: "template.meeting_reschedule", promptKey: "template.meeting_reschedule.prompt", suggestedTone: "polished"),
    AIWriterTemplate(id: "apology", emoji: "\u{1F64F}", nameKey: "template.apology", promptKey: "template.apology.prompt", suggestedTone: "apologetic"),
    AIWriterTemplate(id: "thank_you", emoji: "\u{1F64F}", nameKey: "template.thank_you", promptKey: "template.thank_you.prompt", suggestedTone: "friendly"),
    AIWriterTemplate(id: "birthday", emoji: "\u{1F382}", nameKey: "template.birthday", promptKey: "template.birthday.prompt", suggestedTone: "enthusiastic"),
    AIWriterTemplate(id: "complaint", emoji: "\u{1F4DD}", nameKey: "template.complaint", promptKey: "template.complaint.prompt", suggestedTone: "confident"),
    AIWriterTemplate(id: "follow_up", emoji: "\u{1F504}", nameKey: "template.follow_up", promptKey: "template.follow_up.prompt", suggestedTone: "professional"),
    AIWriterTemplate(id: "cold_outreach", emoji: "\u{1F44B}", nameKey: "template.cold_outreach", promptKey: "template.cold_outreach.prompt", suggestedTone: "persuasive"),
    AIWriterTemplate(id: "dating", emoji: "\u{1F495}", nameKey: "template.dating", promptKey: "template.dating.prompt", suggestedTone: "witty"),
    AIWriterTemplate(id: "social_caption", emoji: "\u{1F4F8}", nameKey: "template.social_caption", promptKey: "template.social_caption.prompt", suggestedTone: "social"),
    AIWriterTemplate(id: "rsvp", emoji: "\u{2709}\u{FE0F}", nameKey: "template.rsvp", promptKey: "template.rsvp.prompt", suggestedTone: "friendly"),
    AIWriterTemplate(id: "congratulations", emoji: "\u{1F389}", nameKey: "template.congratulations", promptKey: "template.congratulations.prompt", suggestedTone: "enthusiastic"),
]
