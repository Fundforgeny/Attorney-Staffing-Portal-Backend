ActiveAdmin.register AdminUser do
  menu if: proc { current_admin_user&.full_access? }

  permit_params :email, :first_name, :last_name, :contact_number,
                :password, :password_confirmation, :role

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
    column :role
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
      row :role
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
      f.input :role, as: :select, collection: AdminUser.roles.keys.map { |key| [key.humanize, key] }
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

    if request.post?
      new_pw  = params[:new_password].to_s.strip
      confirm = params[:new_password_confirmation].to_s.strip

      error = if new_pw.blank?
                "Password cannot be blank."
              elsif new_pw.length < 8
                "Password must be at least 8 characters."
              elsif new_pw != confirm
                "Password and confirmation do not match."
              end

      if error.nil?
        if @admin_user.update(password: new_pw, password_confirmation: confirm)
          # Re-sign-in to prevent Devise from invalidating the session after
          # the encrypted_password changes (only needed when resetting own account)
          bypass_sign_in(@admin_user) if current_admin_user == @admin_user
          flash[:notice] = "Password for #{@admin_user.email} has been reset successfully."
          redirect_to admin_admin_user_path(@admin_user) and return
        else
          flash.now[:error] = "Failed: #{@admin_user.errors.full_messages.join(', ')}"
        end
      else
        flash.now[:error] = error
      end
    end

    @page_title = "Reset Password — #{@admin_user.email}"
    render "admin/admin_users/reset_password", layout: "active_admin"
  end

  # ── Action Item Button on Show Page ────────────────────────────────────────
  action_item :reset_password, only: :show do
    link_to "Reset Password",
            reset_password_admin_admin_user_path(resource),
            class: "button"
  end

  controller do
    before_action :require_full_access!

    private

    def require_full_access!
      return if current_admin_user&.full_access?

      redirect_to admin_root_path, alert: "Only Fund Forge admins can manage admin users."
    end
  end
end
