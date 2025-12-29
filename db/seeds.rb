# Creating Law firm agency
Firms.create(name: "AR Assocites", primary_color: "#45370C4", secondary_color: "#3dc242", description: "This is heavy law firm agency")

use = User.create( email: "testuser1@example.com", password: "Password!123", password_confirmation: "Password!123")

user.create_attorney_profile!(
	user: user,
	firm: firm,
	ghl_contact_id: 123456,
	license_states: ["California", "New York"],
	source: "LinkedIn Import",
	tags: ["senior", "billing-rate-500+"],
	practice_areas: ["Corporate Law", "Mergers & Acquisitions", "Intellectual Property"],
	bar_number: "CA-567890",
	jurisdiction: "California",
	specialties: "Specialized in tech startup mergers and venture ca...",
	years_experience: 12,
	bio: "Sarah is a seasoned corporate attorney with over 1...",
	created_at: "2025-12-25 09:20:11.275655000 +0000",
	updated_at: "2025-12-25 09:20:11.275655000 +0000"
)
