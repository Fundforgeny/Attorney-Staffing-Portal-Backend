ActiveAdmin.register AdminUser do
  permit_params :email, :first_name, :last_name, :contact_number,
                :password, :password_confirmation

  filter :email
  filter :first_name
  filter :last_name
  filter :created_at

  # ── Index ──────────────────────────────────────────────────────────────────
  index do
    selectable_column
    id_column
    column :first_name
    column :last_name
    column :email
    column :contact_number
    column :created_at
    column :updated_at
    actions defaults: true do |admin_user|
      item "Reset Password",
           reset_password_admin_admin_user_path(admin_user),
           class: "member_link"
    end
  end

  # ── Show ───────────────────────────────────────────────────────────────────
  show do
    attributes_table do
      row :id
      row :first_name
      row :last_name
      row :email
      row :contact_number
      row :created_at
      row :updated_at
    end
  end

  # ── Form ───────────────────────────────────────────────────────────────────
  form do |f|
    f.inputs "Account Details" do
      f.input :first_name
      f.input :last_name
      f.input :email
      f.input :contact_number
    end
    f.inputs "Set Password" do
      f.input :password,
              hint: "Leave blank to keep the current password",
              input_html: { autocomplete: "new-password" }
      f.input :password_confirmation,
              input_html: { autocomplete: "new-password" }
    end
    f.actions
  end

  # ── Reset Password Action (GET + POST) ─────────────────────────────────────
  member_action :reset_password, method: [:get, :post] do
    @admin_user = AdminUser.find(params[:id])
    @error      = nil
    @success    = false

    if request.post?
      new_pw   = params[:new_password].to_s.strip
      confirm  = params[:new_password_confirmation].to_s.strip

      if new_pw.blank?
        @error = "Password cannot be blank."
      elsif new_pw.length < 8
        @error = "Password must be at least 8 characters."
      elsif new_pw != confirm
        @error = "Password and confirmation do not match."
      else
        if @admin_user.update(password: new_pw, password_confirmation: confirm)
          flash[:notice] = "Password for #{@admin_user.email} has been reset successfully."
          redirect_to admin_admin_user_path(@admin_user) and return
        else
          @error = "Failed: #{@admin_user.errors.full_messages.join(', ')}"
        end
      end
    end

    # Render the form inline using Arbre
    render layout: "active_admin" do
      columns do
        column do
          panel "Reset Password for #{@admin_user.email}" do
            if @error
              div class: "flash flash_error" do
                @error
              end
            end

            active_admin_form_for @admin_user,
                                  url: reset_password_admin_admin_user_path(@admin_user),
                                  html: { method: :post } do |f|
              f.inputs "New Password" do
                f.input :password,
                        label: "New Password",
                        hint: "Minimum 8 characters",
                        input_html: {
                          name: "new_password",
                          id: "new_password",
                          autocomplete: "new-password"
                        }
                f.input :password_confirmation,
                        label: "Confirm New Password",
                        input_html: {
                          name: "new_password_confirmation",
                          id: "new_password_confirmation",
                          autocomplete: "new-password"
                        }
              end
              f.actions do
                f.action :submit, label: "Reset Password"
                f.cancel_link admin_admin_user_path(@admin_user)
              end
            end
          end
        end
      end
    end
  end

  # ── Action Item Button on Show Page ────────────────────────────────────────
  action_item :reset_password, only: :show do
    link_to "Reset Password",
            reset_password_admin_admin_user_path(resource),
            class: "button"
  end
end
