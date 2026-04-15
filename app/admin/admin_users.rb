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
           method: :get,
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

  # ── Password Reset Member Action ───────────────────────────────────────────
  # GET  /admin/admin_users/:id/reset_password  → show the reset form
  # POST /admin/admin_users/:id/reset_password  → apply the new password
  member_action :reset_password, method: [:get, :post] do
    @admin_user = AdminUser.find(params[:id])

    if request.post?
      new_password = params[:new_password].to_s.strip
      confirmation = params[:new_password_confirmation].to_s.strip

      if new_password.blank?
        flash[:error] = "Password cannot be blank."
        render :reset_password and return
      end

      if new_password != confirmation
        flash[:error] = "Password and confirmation do not match."
        render :reset_password and return
      end

      if new_password.length < 8
        flash[:error] = "Password must be at least 8 characters."
        render :reset_password and return
      end

      if @admin_user.update(password: new_password, password_confirmation: confirmation)
        flash[:notice] = "Password for #{@admin_user.email} has been reset successfully."
        redirect_to admin_admin_user_path(@admin_user)
      else
        flash[:error] = "Failed to reset password: #{@admin_user.errors.full_messages.join(', ')}"
        render :reset_password
      end
    end
    # GET → just render the form view
  end

  action_item :reset_password, only: :show do
    link_to "Reset Password",
            reset_password_admin_admin_user_path(resource),
            class: "button"
  end
end
