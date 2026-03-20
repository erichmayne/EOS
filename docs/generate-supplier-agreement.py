from fpdf import FPDF

class AgreementPDF(FPDF):
    def header(self):
        self.set_font("Helvetica", "B", 9)
        self.set_text_color(0, 122, 204)
        self.cell(0, 6, "TensorDock.com, Inc", align="L")
        self.ln(3)
        self.set_draw_color(0, 122, 204)
        self.line(self.l_margin, self.get_y(), self.w - self.r_margin, self.get_y())
        self.ln(6)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    def section_title(self, title):
        self.set_font("Helvetica", "B", 13)
        self.set_text_color(30, 30, 30)
        self.ln(4)
        self.cell(0, 8, title, new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(60, 60, 60)
        self.line(self.l_margin, self.get_y(), self.w - self.r_margin, self.get_y())
        self.ln(4)

    def sub_section(self, title):
        self.set_font("Helvetica", "B", 11)
        self.set_text_color(40, 40, 40)
        self.ln(2)
        self.cell(0, 7, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def body_text(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(50, 50, 50)
        self.multi_cell(0, 5.5, text)
        self.ln(2)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(50, 50, 50)
        x = self.get_x()
        self.cell(8, 5.5, "-")
        self.multi_cell(0, 5.5, text)
        self.ln(1)

    def signature_line(self, label, width=80):
        y = self.get_y()
        self.set_draw_color(80, 80, 80)
        self.line(self.get_x(), y, self.get_x() + width, y)
        self.ln(1)
        self.set_font("Helvetica", "", 9)
        self.set_text_color(100, 100, 100)
        self.cell(width, 5, label)
        self.ln(8)


pdf = AgreementPDF()
pdf.alias_nb_pages()
pdf.set_auto_page_break(auto=True, margin=20)
pdf.set_margins(25, 20, 25)
pdf.add_page()

# Title
pdf.set_font("Helvetica", "B", 22)
pdf.set_text_color(20, 20, 20)
pdf.cell(0, 12, "Supplier Hosting Agreement", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.ln(6)

pdf.set_font("Helvetica", "", 10)
pdf.set_text_color(100, 100, 100)
pdf.cell(0, 6, "Effective Date: ____________________", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.ln(8)

pdf.body_text(
    'This agreement ("Supplier Hosting Agreement") sets out the legal terms on which '
    'TensorDock.com, Inc of 16192 Coastal Highway, Lewes, Delaware, United States 19958 '
    '("TensorDock") contracts with the individual or entity providing compute power for '
    'the TensorDock Marketplace ("Supplier").'
)

# ── Definitions ──
pdf.section_title("Definitions")

pdf.bullet(
    "End Users are individuals or entities who have registered accounts with TensorDock's "
    "Marketplace product for the purpose of renting computing infrastructure."
)
pdf.bullet(
    "Cloud Services refers to the computing infrastructure rental provided by Supplier "
    "for TensorDock's End Users."
)
pdf.bullet(
    "TensorDock Confidential Information refers to any and all information whether in oral, "
    "written or electronic form sent from TensorDock to Supplier that is not publicly stated "
    "on TensorDock's website, documentation, or press releases or that is not public knowledge. "
    "This includes technical or business expertise, finance details, intellectual property rights, "
    "media assets, strategy plans, product details, and End Users, including such details about "
    "other arrangements or operations of any person, firm, or organization associated with TensorDock."
)
pdf.bullet(
    "Customer Confidential Information refers to any and all information whether in oral, written "
    "or electronic form sent from TensorDock to Supplier about Customer that is not publicly stated "
    "on TensorDock's website, Customer's website, publicly available documentation, or that is not "
    "public knowledge. This includes technical or business expertise, finance details, intellectual "
    "property rights, media assets, strategy plans, product details, and customers, including such "
    "details about other arrangements or operations of any person, firm or organization associated "
    "with Customer."
)
pdf.bullet(
    "Customer Data refers to all data, software, information (including Customer Confidential "
    "Information) which, by Customer's actions, are hosted or processed on the Cloud Services."
)
pdf.bullet(
    "Platform, Marketplace Platform, TensorDock Platform, and TensorDock Marketplace all refer "
    "to the software-as-a-service platform facilitating Customers' access to Suppliers' Cloud Services."
)

# ── TensorDock's Obligations ──
pdf.section_title("TensorDock's Obligations")
pdf.body_text(
    "TensorDock owns and operates the TensorDock Platform, which facilitates access to and use of "
    "Cloud Services hosted by Supplier. TensorDock assists End Users in setting up their projects, "
    "facilitates Customer access to Cloud Services, and provides customer support for End Users when "
    "issues arise, in exchange for taking a fee."
)

# ── Supplier's Obligations ──
pdf.section_title("Supplier's Obligations")
pdf.body_text(
    "Supplier agrees to grant TensorDock a non-exclusive license to advertise, list, and provide "
    "details of Supplier's Cloud Services on the TensorDock Marketplace and serve the Cloud Services "
    "to the End User at the Supplier's set price."
)
pdf.body_text(
    "Supplier is responsible for reliably operating Cloud Services and indemnifies TensorDock and "
    "Customer for any breach of obligations. In addition, Supplier will implement both physical and "
    "network security measures to guarantee that Cloud Services will not be accessed by third parties "
    "to ensure the security of Customer Data and Confidential Customer Information."
)

# SLA
pdf.sub_section("Supplier's Service Level Agreement (SLA)")
pdf.body_text(
    "Supplier understands that TensorDock provides an SLA to Customer; thus, if Supplier does not "
    "achieve 100% uptime, TensorDock reserves the right to charge Supplier a penalty to uphold "
    "TensorDock's SLA. All penalties are transferred to Customer as remediation for the downtimes, "
    "and TensorDock does not profit from such transactions."
)

pdf.bullet(
    "Short Network Disconnects or Reboots: If any physical servers undergo unplanned reboots or "
    "disconnect from TensorDock's redundant monitoring service for two (2) or more continuous minutes "
    "but less than one hour due to the Supplier's fault, TensorDock will charge Supplier a penalty "
    "worth 5 hours multiplied by the hourly earnings of the server when the interruption occurred. "
    "For instance, if Customer was running a workload of $1/hr that was interrupted by a reboot, "
    "TensorDock will deduct $1 * 5 = $5 from Supplier's balance and deposit that into Customer's "
    "balance. TensorDock understands and accepts that the cloud security policies of Supplier may "
    "interfere with the workloads of the Customers, and may cause disconnections related to the "
    "identification of malicious inbound or outbound traffic. These types of interruptions will not "
    "be considered downtime, and Supplier will not pay any penalties for such interruptions."
)
pdf.bullet(
    "Extended Downtimes: If any physical servers undergo unscheduled extended downtimes of one hour "
    "or greater, TensorDock will charge Supplier a penalty of five (5) multiplied by the hourly "
    "earnings of the server when the interruption started. For instance, if Customer was running a "
    "workload of $1/hr that was interrupted by a one-day interruption, TensorDock will deduct "
    "5 * $1 * 24 = $120 from Supplier's balance and deposit that into Customer's balance."
)
pdf.bullet(
    "Data Loss: Supplier understands that Customer rents Supplier's hardware to run mission-critical "
    "workloads, and that losing data might lead to Customer needing to re-compute weeks' worth of "
    "previous work. If Supplier's hardware loses Customer data, TensorDock reserves the right to "
    "charge Supplier a penalty up to but not exceeding Supplier's previous month's earnings on the "
    "impacted server to compensate Customer."
)

# Supplier Rights
pdf.sub_section("Supplier Rights")
pdf.body_text(
    "TensorDock does not accept any responsibility or liability for unauthorized access to the Cloud "
    "Services, misuse of the Cloud Services by the customer, or any damages including but not limited "
    "to effect of interfering adversely with, the operation of any hardware or software, including any "
    "bugs, worms, logic bombs, Trojan horses or any other such programs; or use of the Cloud Services "
    "in a manner which infringes supplier's intellectual property rights."
)
pdf.body_text(
    "However, if and only if there is documented evidence of illegal activities occurring on Cloud "
    "Services directly consumed by Customer, then Supplier may ask to terminate this contract. In the "
    "event of this, TensorDock shall only pay for the prorated time of services consumed by customer "
    "before the notice, and TensorDock shall receive fourteen (14) days of free access to all previously "
    "provisioned Cloud Services to migrate Customer Data to a different supplier."
)

# ── IP Rights ──
pdf.section_title("Intellectual Property Rights")
pdf.body_text(
    "TensorDock retains ownership of all intellectual property rights in the TensorDock Marketplace and "
    "any materials created by TensorDock in the course of fulfilling its obligations. In addition, "
    "Supplier retains ownership of all intellectual property rights in supplier data, and Customer shall "
    "retain ownership of all intellectual property rights of their Customer Data and Customer Confidential "
    "Information."
)
pdf.body_text(
    "TensorDock may use any feedback and suggestions for improvement relating to the Marketplace provided "
    "by the supplier without charge or limitation."
)
pdf.body_text(
    "The supplier shall indemnify TensorDock and/or customer from any losses, claims, damages, liability, "
    "costs, and expenses incurred by them as a result of any action or claim that the transmission, receipt, "
    "copying, installation, use, possession, or other utilization of data or Cloud Services infringes the "
    "intellectual property rights of any supplier."
)

# ── Confidentiality ──
pdf.section_title("Confidentiality")
pdf.body_text(
    "Supplier agrees to use TensorDock's Confidential Information only in the exercise of its rights and "
    "performance of its obligations under the agreement and not to disclose TensorDock's Confidential "
    "Information to any other party, except as required by law, court, governmental, regulatory or "
    "supervisory authority, or any other authority of competent jurisdiction."
)
pdf.body_text(
    "Supplier also agrees not to disclose any Customer Confidential Information or Customer Data and shall "
    "assume liability for TensorDock and Customer from any losses, damages, liability, costs, and expenses "
    "they may incur as a result of any breach of their confidentiality obligations."
)
pdf.body_text(
    "The supplier shall not access Customer Data or any Cloud Services used by the customer, even hosted by "
    "Supplier, without prior written consent from TensorDock."
)

# ── Non-Circumvention ──
pdf.section_title("Non-Circumvention Policy")
pdf.body_text(
    "Supplier acknowledges and agrees that a portion of TensorDock's compensation is tied to facilitating "
    "Customer's access to the Cloud Services."
)
pdf.body_text(
    "During the term of the Supplier Hosting Agreement, Supplier agrees not to engage in any attempts to "
    "contact, solicit, communicate with, or seek the contact information of other Customers or suppliers "
    "for the purpose of using or providing Cloud Services outside of TensorDock; and not to contact or sell "
    "Cloud Services to any customers who have purchased TensorDock's Services during the Supplier Hosting "
    "Agreement term or within the 12 months preceding the Supplier Hosting Agreement without paying a ten "
    "percent (10%) commission of Customer's transaction volume on Supplier to TensorDock; or individuals or "
    "entities with whom TensorDock is currently or has been in discussions regarding the sale of TensorDock "
    "Services during the term of the Agreement or within the 12 months preceding the Agreement without paying "
    "a ten percent (10%) commission of Customer's transaction volume on Supplier to TensorDock."
)
pdf.body_text(
    "For a period of 48 months after the Supplier Hosting Agreement's termination, Supplier agrees that, "
    "except for general recruitment efforts open to all applicants and not specifically aimed at TensorDock, "
    "supplier shall not, without prior written consent from TensorDock, engage in directly or indirectly seek "
    "to recruit, hire, or engage in any contractual relationship with any employees or personnel of TensorDock; "
    "or to provide assistance or instructions to any third party regarding the recruitment, employment, "
    "contracting, or subcontracting of personnel from TensorDock."
)

# ── Warranties ──
pdf.section_title("Warranties")
pdf.body_text(
    "Both parties represent and warrant that they have the power and authority to enter into and perform their "
    "obligations under the agreement. Supplier represents and warrants that they have the right to grant "
    "TensorDock.com, Inc the rights to use the Cloud Services and that they will provide complete and accurate "
    "information about Cloud Services."
)
pdf.body_text(
    "All other warranties, conditions, terms, undertakings, or obligations, whether express or implied, are "
    "excluded to the fullest extent allowed by the applicable laws."
)

# ── Liabilities ──
pdf.section_title("Liabilities")
pdf.body_text(
    "TensorDock is not responsible for any indirect, special, or consequential loss or damage, regardless of "
    "the cause (contract, tort, breach of statutory duty, or otherwise) related to the Agreement or any related "
    "activities. TensorDock's maximum total liability to supplier for all claims (regardless of the cause) "
    "related to the Agreement or any related activities shall not exceed the total payouts withdrawn by Supplier "
    "via Stripe Connect over the previous ninety (90) days."
)

# ── Contract Termination ──
pdf.section_title("Contract Termination")
pdf.body_text(
    "In the event of an unplanned disconnect of Cloud Services from Supplier's hosting site to the public "
    "internet, data breach, or data loss of any sort, TensorDock reserves the right to terminate this contract "
    "and have one (1) free week to remove Customer Data from Supplier's Cloud Services. TensorDock may also "
    "immediately terminate the Supplier Hosting Agreement, deactivate supplier's account, and/or seize previous "
    "earnings if supplier materially or persistently breaches the Agreement."
)
pdf.body_text(
    "Under normal circumstances, TensorDock may terminate this Supplier Hosting Agreement with one (1) week of "
    "notice. Also, this agreement will terminate if TensorDock ceases to exist, or if the provision of Cloud "
    "Services or TensorDock.com, Inc Services becomes illegal. TensorDock will make reasonable efforts to give "
    "supplier notice beforehand, but this may not always be possible."
)
pdf.body_text(
    "If Customers are running actively using Supplier's Cloud Services, Supplier must give at least one month of "
    "written notice via email to TensorDock before terminating this agreement or decommissioning servers, but if "
    "no Customers are actively using Supplier's Cloud Services, Supplier may remove Supplier's servers or "
    "terminate this agreement without notice."
)

# ── Payment ──
pdf.section_title("Payment")
pdf.body_text(
    "TensorDock shall give Supplier the ability to set their own a la carte per-resource pricing. For on-demand "
    "usage, TensorDock will track and monitor usage by Customers and credit Supplier's account accordingly. Once "
    "Supplier's account surpasses $250 of account balance, Supplier will be able to withdraw their balance."
)
pdf.body_text(
    "If Supplier and TensorDock agree on providing monthly or longer term subscription billing options for "
    "customers, earnings from monthly or longer subscription servers will be deposited at the end of each "
    "calendar month."
)
pdf.body_text(
    "TensorDock will take a twenty-five percent (25%) fee from Supplier's earnings."
)
pdf.body_text(
    "Supplier will create a Stripe Connect account on the TensorDock Platform linking their bank account to "
    "the TensorDock Platform. Supplier agrees to withdraw their accumulated funds at least once during each "
    "month. Supplier may withdraw their balance spread over multiple days each month but agrees to only withdraw "
    "at most one-thousand US dollars ($1,000) within a single 24-hour period through Stripe Connect. Stripe will "
    "convert the currency to Supplier's preferred currency at a mid-market price, with slippage paid for by "
    "TensorDock. Alternatively, Supplier can provide TensorDock a bank account wiring details, and TensorDock "
    "will wire Supplier's account balance at the end of each month, in Euros."
)
pdf.body_text(
    "Supplier is responsible for the accuracy and completeness of their bank account information listed in "
    "Stripe Connect, and TensorDock is not liable for delays or losses resulting from withdrawing money to an "
    "incorrect payment method."
)

# ── Other Important Information ──
pdf.section_title("Other Important Information")
pdf.body_text(
    "Suppliers can review the Agreement at any time on TensorDock's website. TensorDock reserves the right to "
    "change the Agreement at any time by posting updates to its website periodically. TensorDock will submit a "
    "written (email) notification with the statement of changes and/or an Agreement Addendum to this contract to "
    "be validated and agreed by Supplier. If TensorDock is required to do so by law, TensorDock will notify the "
    "Supplier by way of email, and such changes shall take effect within the minimum timeframe as allowed by law. "
    "If Supplier does not agree with the changes, it may terminate the Agreement by providing TensorDock with "
    "notice within a fourteen (14) day period, otherwise supplier will be deemed to have accepted the changes."
)
pdf.body_text(
    "Suppliers can contact TensorDock at any time by emailing hello@tensordock.com."
)
pdf.body_text(
    "Supplier may not assign, transfer, sub-license or deal in any other manner with any or all of its rights or "
    "obligations under the Agreement, without TensorDock's prior written consent. TensorDock reserves the right "
    "to transfer, assign, sub-contract or deal in any other manner with any or all of its rights or obligations "
    "under the Agreement, without notifying Supplier or receiving their consent."
)
pdf.body_text(
    "The Supplier Hosting Agreement constitutes the entire agreement between TensorDock and Supplier and "
    "supersedes and extinguishes all previous agreements, promises, assurances, warranties, representations and "
    "understandings between them, whether written or oral, relating to its subject matter."
)
pdf.body_text(
    "The Supplier Hosting Agreement and any dispute or claim arising out of, or in connection with it, its "
    "subject matter or formation (including non-contractual disputes or claims) shall be governed by, and "
    "construed in accordance with, the laws of the state of Delaware in the United States."
)
pdf.body_text(
    "The parties irrevocably agree that this agreement and any dispute or claim arising out of, or in connection "
    "with it, shall be dealt with via arbitration. The number of arbitrators shall be one. The seat, or legal "
    "place, of arbitration shall be Delaware. The language to be used in the arbitral proceedings shall be English."
)
pdf.body_text(
    "Any obligation of TensorDock under the Supplier Hosting Agreement to comply or ensure compliance with any "
    "law shall be limited to compliance only with laws where TensorDock.com, Inc is established."
)

# ═══════════════════════════════════════════════════════════════
#  SIGNATURE (inline, no new page)
# ═══════════════════════════════════════════════════════════════
pdf.section_title("Supplier Acknowledgement & Signature")

pdf.set_font("Helvetica", "", 10)
pdf.set_text_color(50, 50, 50)
pdf.multi_cell(0, 5.5,
    "By signing below, the Supplier acknowledges that they have read, understood, and agree to be "
    "bound by all terms and conditions set forth in this Supplier Hosting Agreement."
)
pdf.ln(6)

pdf.set_font("Helvetica", "", 10)
pdf.set_text_color(50, 50, 50)
pdf.set_draw_color(80, 80, 80)

pdf.cell(45, 6, "Business Name:")
pdf.line(pdf.get_x(), pdf.get_y() + 6, pdf.get_x() + 110, pdf.get_y() + 6)
pdf.ln(12)

pdf.cell(45, 6, "Address:")
pdf.line(pdf.get_x(), pdf.get_y() + 6, pdf.get_x() + 110, pdf.get_y() + 6)
pdf.ln(12)

pdf.cell(45, 6, "")
pdf.line(pdf.get_x(), pdf.get_y() + 6, pdf.get_x() + 110, pdf.get_y() + 6)
pdf.ln(12)

pdf.cell(45, 6, "Signature:")
pdf.line(pdf.get_x(), pdf.get_y() + 6, pdf.get_x() + 110, pdf.get_y() + 6)
pdf.ln(12)

pdf.cell(45, 6, "Print Name / Title:")
pdf.line(pdf.get_x(), pdf.get_y() + 6, pdf.get_x() + 110, pdf.get_y() + 6)
pdf.ln(12)

pdf.cell(45, 6, "Date:")
pdf.line(pdf.get_x(), pdf.get_y() + 6, pdf.get_x() + 110, pdf.get_y() + 6)
pdf.ln(6)

# Output
output_path = "/Users/emayne/morning-would/docs/Supplier-Hosting-Agreement.pdf"
pdf.output(output_path)
print(f"PDF generated: {output_path}")
