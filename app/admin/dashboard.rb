ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: "Dashboard"

  content title: "Admin Dashboard" do
    total_users = User.count
    total_clients = User.client.count
    total_attorneys = User.attorney.count
    total_firms = Firm.count

    total_plans = Plan.count
    active_plans = Plan.active.count
    completed_plans = Plan.completed.count
    cancelled_plans = Plan.cancelled.count

    total_payments = Payment.count
    succeeded_payments = Payment.succeeded.count
    pending_payments = Payment.pending.count
    failed_payments = Payment.failed.count

    total_revenue = Payment.succeeded.sum(:total_payment_including_fee) || 0
    this_month_revenue = Payment.succeeded.where(
      paid_at: Date.current.beginning_of_month..Date.current.end_of_day
    ).sum(:total_payment_including_fee) || 0

    total_agreements = Agreement.count
    signed_agreements = Agreement.where.not(signed_at: nil).count

    lead_count = User.joins(:plans)
                     .where("plans.magic_link_token IS NOT NULL AND plans.magic_link_token != ''")
                     .where.not(id: Payment.where(status: :succeeded).select(:user_id))
                     .distinct
                     .count

    monthly_labels = []
    monthly_revenue = []
    monthly_success_payments = []
    monthly_new_plans = []

    5.downto(0) do |i|
      month_start = i.months.ago.beginning_of_month
      month_end = month_start.end_of_month
      monthly_labels << month_start.strftime("%b %Y")

      monthly_revenue << Payment.succeeded.where(
        "COALESCE(payments.paid_at, payments.created_at) BETWEEN ? AND ?",
        month_start,
        month_end
      ).sum(:total_payment_including_fee).to_f

      monthly_success_payments << Payment.succeeded.where(
        "COALESCE(payments.paid_at, payments.created_at) BETWEEN ? AND ?",
        month_start,
        month_end
      ).count

      monthly_new_plans << Plan.where(created_at: month_start..month_end).count
    end

    payment_status_data = [
      succeeded_payments,
      pending_payments,
      failed_payments
    ]

    plan_status_data = [
      active_plans,
      completed_plans,
      cancelled_plans
    ]

    top_firms = Firm.left_joins(:users)
                    .group(:id, :name)
                    .order("COUNT(users.id) DESC")
                    .limit(5)
                    .pluck(:name, Arel.sql("COUNT(users.id)"))

    recent_payments = Payment.order(created_at: :desc).limit(6)
    recent_plans = Plan.order(created_at: :desc).limit(6)

    div class: "aa-dashboard" do
      div class: "aa-dashboard__hero" do
        h2 "Admin Intelligence Dashboard", class: "aa-dashboard__title"
        para class: "aa-dashboard__subtitle" do
          text_node "Track growth, revenue and operations in one place."
        end
      end

      div class: "aa-dashboard__kpis" do
        [
          { label: "Users", value: total_users, meta: "#{total_clients} clients / #{total_attorneys} attorneys", tone: "primary" },
          { label: "Revenue", value: number_to_currency(total_revenue), meta: "This month #{number_to_currency(this_month_revenue)}", tone: "warning" },
          { label: "Payments", value: total_payments, meta: "#{succeeded_payments} succeeded", tone: "info" },
          { label: "Plans", value: total_plans, meta: "#{active_plans} active", tone: "success" },
          { label: "Leads", value: lead_count, meta: "Unpaid magic-link users", tone: "danger" },
          { label: "Agreements", value: total_agreements, meta: "#{signed_agreements} signed", tone: "purple" }
        ].each do |kpi|
          div class: "aa-kpi aa-kpi--#{kpi[:tone]}" do
            para class: "aa-kpi__label" do
              text_node kpi[:label]
            end
            para class: "aa-kpi__value" do
              text_node kpi[:value]
            end
            para class: "aa-kpi__meta" do
              text_node kpi[:meta]
            end
          end
        end
      end

      div class: "aa-dashboard-tabs", data: { controller: "dashboard-tabs" } do
        div class: "aa-dashboard-tabs__nav" do
          button "Overview", class: "aa-tab-btn is-active", type: "button", data: { tab_target: "overview" }
          button "Revenue", class: "aa-tab-btn", type: "button", data: { tab_target: "revenue" }
          button "Operations", class: "aa-tab-btn", type: "button", data: { tab_target: "ops" }
        end

        div class: "aa-dashboard-tabs__panel is-active", data: { tab_panel: "overview" } do
          div class: "aa-grid aa-grid--2" do
            div class: "aa-card" do
              h3 "Payment Status Mix", class: "aa-card__title"
              div class: "aa-chart-wrap" do
                canvas id: "aaPaymentStatusChart", height: "180"
              end
            end

            div class: "aa-card" do
              h3 "Plan Status Mix", class: "aa-card__title"
              div class: "aa-chart-wrap" do
                canvas id: "aaPlanStatusChart", height: "180"
              end
            end
          end

          div class: "aa-grid aa-grid--2" do
            div class: "aa-card" do
              h3 "Top Firms by Users", class: "aa-card__title"
              if top_firms.any?
                table class: "aa-mini-table" do
                  thead do
                    tr do
                      th "Firm"
                      th "Users"
                    end
                  end
                  tbody do
                    top_firms.each do |firm_name, user_count|
                      tr do
                        td(firm_name.presence || "Unnamed Firm")
                        td user_count
                      end
                    end
                  end
                end
              else
                div "No firm data available.", class: "aa-empty"
              end
            end

            div class: "aa-card" do
              h3 "Quick Actions", class: "aa-card__title"
              div class: "aa-actions-grid" do
                para { link_to "Users", admin_users_path, class: "button" }
                para { link_to "Plans", admin_plans_path, class: "button" }
                para { link_to "Firms", admin_firms_path, class: "button" }
                para { link_to "Leads", admin_leads_path, class: "button" }
              end
            end
          end
        end

        div class: "aa-dashboard-tabs__panel", data: { tab_panel: "revenue" } do
          div class: "aa-card" do
            h3 "Revenue Trend (Last 6 Months)", class: "aa-card__title"
            div class: "aa-chart-wrap aa-chart-wrap--lg" do
              canvas id: "aaRevenueTrendChart", height: "110"
            end
          end

          div class: "aa-grid aa-grid--2" do
            div class: "aa-card" do
              h3 "Monthly Succeeded Payments", class: "aa-card__title"
              div class: "aa-chart-wrap" do
                canvas id: "aaPaymentVolumeChart", height: "180"
              end
            end

            div class: "aa-card" do
              h3 "Recent Payments", class: "aa-card__title"
              if recent_payments.any?
                div class: "aa-table-scroll" do
                  table class: "aa-mini-table" do
                    thead do
                      tr do
                        th "User"
                        th "Type"
                        th "Amount"
                        th "Status"
                      end
                    end
                    tbody do
                      recent_payments.each do |payment|
                        tr do
                          td(payment.user&.email || "N/A")
                          td(payment.payment_type.to_s.humanize)
                          td(number_to_currency(payment.total_payment_including_fee || 0))
                          td(status_tag(payment.status))
                        end
                      end
                    end
                  end
                end
              else
                div "No payments found.", class: "aa-empty"
              end
            end
          end
        end

        div class: "aa-dashboard-tabs__panel", data: { tab_panel: "ops" } do
          div class: "aa-grid aa-grid--2" do
            div class: "aa-card" do
              h3 "New Plans (Last 6 Months)", class: "aa-card__title"
              div class: "aa-chart-wrap" do
                canvas id: "aaPlanCreationChart", height: "180"
              end
            end

            div class: "aa-card" do
              h3 "Latest Plans", class: "aa-card__title"
              if recent_plans.any?
                div class: "aa-table-scroll" do
                  table class: "aa-mini-table" do
                    thead do
                      tr do
                        th "Plan"
                        th "User"
                        th "Total"
                        th "Status"
                      end
                    end
                    tbody do
                      recent_plans.each do |plan|
                        tr do
                          td plan.name
                          td(plan.user&.email || "N/A")
                          td number_to_currency(plan.total_payment || 0)
                          td status_tag(plan.status)
                        end
                      end
                    end
                  end
                end
              else
                div "No plans found.", class: "aa-empty"
              end
            end
          end
        end
      end
    end

    script_data = {
      labels: monthly_labels,
      monthly_revenue: monthly_revenue,
      monthly_success_payments: monthly_success_payments,
      monthly_new_plans: monthly_new_plans,
      payment_status: payment_status_data,
      plan_status: plan_status_data
    }.to_json

    text_node raw(
      "<script src='https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js'></script>"
    )

    text_node raw(
      <<~SCRIPT
        <script>
          (function() {
            var data = #{script_data};

            function initTabs() {
              var tabsRoot = document.querySelector(".aa-dashboard-tabs");
              if (!tabsRoot) return;

              var btns = tabsRoot.querySelectorAll(".aa-tab-btn");
              var panels = tabsRoot.querySelectorAll(".aa-dashboard-tabs__panel");

              btns.forEach(function(btn) {
                btn.addEventListener("click", function() {
                  var target = btn.getAttribute("data-tab-target");

                  btns.forEach(function(b) { b.classList.remove("is-active"); });
                  panels.forEach(function(p) { p.classList.remove("is-active"); });

                  btn.classList.add("is-active");
                  var panel = tabsRoot.querySelector('[data-tab-panel="' + target + '"]');
                  if (panel) panel.classList.add("is-active");
                });
              });
            }

            function chartDefaults() {
              return {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: { labels: { color: "#344054", boxWidth: 12, boxHeight: 12 } },
                  tooltip: {
                    backgroundColor: "rgba(17,50,212,0.95)",
                    padding: 10,
                    cornerRadius: 8
                  }
                },
                scales: {
                  x: { ticks: { color: "#667085" }, grid: { color: "rgba(17,50,212,0.06)" } },
                  y: { ticks: { color: "#667085" }, grid: { color: "rgba(17,50,212,0.06)" } }
                }
              };
            }

            function makeCharts() {
              if (!window.Chart) return;

              var blue = "#1132d4";
              var green = "#28a745";
              var yellow = "#ffc107";
              var red = "#dc3545";
              var cyan = "#17a2b8";
              var purple = "#6f42c1";

              var paymentCtx = document.getElementById("aaPaymentStatusChart");
              if (paymentCtx) {
                new Chart(paymentCtx, {
                  type: "doughnut",
                  data: {
                    labels: ["Succeeded", "Pending", "Failed"],
                    datasets: [{
                      data: data.payment_status,
                      backgroundColor: ["#FDD365", "rgba(253, 211, 101, 0.82)", "rgba(253, 211, 101, 0.64)"],
                      borderWidth: 0
                    }]
                  },
                  options: Object.assign(chartDefaults(), {
                    cutout: "62%",
                    scales: {}
                  })
                });
              }

              var planCtx = document.getElementById("aaPlanStatusChart");
              if (planCtx) {
                new Chart(planCtx, {
                  type: "pie",
                  data: {
                    labels: ["Active", "Completed", "Cancelled"],
                    datasets: [{
                      data: data.plan_status,
                      backgroundColor: ["#1F6CB0", "rgba(31, 108, 176, 0.82)", "rgba(31, 108, 176, 0.64)"],
                      borderWidth: 0
                    }]
                  },
                  options: Object.assign(chartDefaults(), { scales: {} })
                });
              }

              var revenueCtx = document.getElementById("aaRevenueTrendChart");
              if (revenueCtx) {
                new Chart(revenueCtx, {
                  type: "line",
                  data: {
                    labels: data.labels,
                    datasets: [{
                      label: "Revenue",
                      data: data.monthly_revenue,
                      borderColor: blue,
                      backgroundColor: "rgba(17,50,212,0.15)",
                      fill: true,
                      tension: 0.35,
                      pointRadius: 3
                    }]
                  },
                  options: chartDefaults()
                });
              }

              var volumeCtx = document.getElementById("aaPaymentVolumeChart");
              if (volumeCtx) {
                new Chart(volumeCtx, {
                  type: "bar",
                  data: {
                    labels: data.labels,
                    datasets: [{
                      label: "Succeeded Payments",
                      data: data.monthly_success_payments,
                      backgroundColor: "rgba(111,66,193,0.75)",
                      borderRadius: 8
                    }]
                  },
                  options: chartDefaults()
                });
              }

              var plansCtx = document.getElementById("aaPlanCreationChart");
              if (plansCtx) {
                new Chart(plansCtx, {
                  type: "bar",
                  data: {
                    labels: data.labels,
                    datasets: [{
                      label: "New Plans",
                      data: data.monthly_new_plans,
                      backgroundColor: "rgba(23,162,184,0.72)",
                      borderRadius: 8
                    }]
                  },
                  options: chartDefaults()
                });
              }
            }

            if (document.readyState === "loading") {
              document.addEventListener("DOMContentLoaded", function() {
                initTabs();
                makeCharts();
              });
            } else {
              initTabs();
              makeCharts();
            }
          })();
        </script>
      SCRIPT
    )
  end
end
