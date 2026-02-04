ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: "Dashboard"

  content title: "Admin Dashboard" do
    para "Welcome to the Staffing Portal Admin. Please select an option from the sidebar to manage your data."
    
    panel "Quick Navigation" do
      div do
        h4 "Users Management"
        para "Manage all users, their profiles, and permissions."
        link_to "View All Users", admin_users_path, class: "button"
      end
      
      div do
        h4 "Firms Management"
        para "Manage law firms and their information."
        link_to "View All Firms", admin_firms_path, class: "button"
      end
    end
  end
end
