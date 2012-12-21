# -*- encoding: utf-8 -*-
class ImportMail < ActiveRecord::Base

  belongs_to :business_partner
  belongs_to :bp_pic

  def ImportMail.import
    Pop3Client.pop_mail do |m, src|
      puts">>>>>>>>>>>>>>>>>>>>>>>>>>> MAIL IMPORT START"
      ActiveRecord::Base::transaction do

        import_mail = ImportMail.new
        
        import_mail.in_reply_to = m.in_reply_to[0] if m.in_reply_to
        import_mail.received_at = m.date
        import_mail.mail_subject = NKF.nkf('-w -J', m.subject)
        import_mail.mail_from = m.from[0]
        import_mail.set_bp
        import_mail.mail_sender_name = NKF.nkf('-w -J', m.from_addrs[0].to_s)
        import_mail.mail_to = m.to.join(",") if m.to
        import_mail.mail_cc = m.cc.join(",") if m.cc
        import_mail.mail_bcc = m.bcc.join(",") if m.bcc
        import_mail.message_source = src
        import_mail.message_id = m.message_id

        # attempt_file�̂���(import_mail_id���K�v)�Ɉ�U�o�^
        import_mail.save!
        
        
        
        #---------- mail_body �������� ----------
        if m.multipart?
          puts">>>>>>>>>>>>>>>>>>>>>>>>>>> MULTIPART MODE"
          # �p�[�g�ɕ�����Ă���(=�ԐM�����[����Y�t�t�@�C�������݂��Ă���)�ꍇ
          m.parts.each do |part|
            puts">>>>>>>>>>>>>>>>>>>>>>>>>>> content_type : #{part.content_type}"
            if part.content_type == 'multipart/alternative'
              puts">>>>>>>>>>>>>>>>>>>>>>>>>>> ALTERNATIVE MODE"
              # multipart/alternative�̏ꍇ�A���[���{���̊܂܂��p�[�g�Ȃ̂ŁA����ɂ��̒��̃p�[�g�𒲂ׂ�B
              part.parts.each do |ppart|
                puts">>>>>>>>>>>>>>>>>>>>>>>>>>> content_type in alternative : #{ppart.content_type}"
                if ppart.content_type == 'text/plain'
                  puts">>>>>>>>>>>>>>>>>>>>>>>>> REGIST MAIL BODY(text/plain in alternative)"
                  # text/plain�̏ꍇ�A���[���{���i�ԐM���ƓY�t�t�@�C���̉\�����E�E�E�j�B
                  import_mail.mail_body = get_encode_body(m, ppart.body)
                  break
                end # ppart.content_type == 'text/plain'
              end # part.parts.each do
              if import_mail.mail_body.blank?
                puts">>>>>>>>>>>>>>>>>>>>>>>>> REGIST MAIL BODY(other in alternative)"
                # ���[���{���ɂ܂������������ĂȂ�(=�v���[���e�L�X�g���Ȃ�����)�ꍇ�A
                # �ŏ���body�̒l���G���R�[�h���đ������
                import_mail.mail_body = get_encode_body(m, part.parts[0].body)
              end # import_mail.mail_body.blank?
            elsif !part.disposition_param('filename').blank?
              # filename������ = �Y�t�t�@�C���Ȃ̂Ńp�X
              puts">>>>>>>>>>>>>>>>>>>>>>>>> REGIST ATTEMPT FILE"
              
              
              #---------- �Y�t�t�@�C�� �������� ----------
              upfile = part.body
              part.base64_decode
              file_name = part.disposition_param('filename')
              
#              if(file_name =~ /=\?ISO-2022-JP\?B\?/)
                file_name = NKF.nkf('-w -J', file_name)
                puts">>>>>>>>>>>>>>>>>>>>>>>>>>> decoded_file_name : #{file_name}"
#              end
              
              attachment_file = AttachmentFile.new
              attachment_file.create_by_import(upfile, import_mail.id, file_name)
              
 #             ActiveRecord::Base.transaction do
 #               attachment_file = AttachmentFile.new
 #               # attachmentFile�ɍ��ڂ����郁�\�b�h
 #               # �e�e�[�u����
 #               attachment_file.parent_table_name = "import_mails"
 #               # �e�e�[�u��Id
 #               attachment_file.parent_id = 200
 #               # �Y�t�t�@�C�����i�I���W�i���̃t�@�C�����j
 #               attachment_file.file_name = file_name
 #               # �g���q
 #               ext = attachment_file.check_and_get_ext(file_name)
 #               attachment_file.extention = ext
 #               
 #               attachment_file.created_user = 'import_mail'
 #               attachment_file.updated_user = 'import_mail'
 #               attachment_file.save!
 #               
 #               # �ۑ�����t�@�C����
 #               store_file_name = attachment_file.create_store_parent_table_name
 #               attachment_file.store(upfile, store_file_name)
 #             end # transaction
              
              #---------- �Y�t�t�@�C�� �����܂� ----------
              
              puts">>>>>>>>>>>>>>>>>>>>>>>>> REGIST ATTEMPT FILE"
              
            elsif part.content_type == 'text/plain'
              # �Y�t�t�@�C���łȂ�text/plain�̏ꍇ�A���[���{���B
              # �㏑�������\������H
              puts">>>>>>>>>>>>>>>>>>>>>>>>> REGIST MAIL BODY(text/plain)"
              import_mail.mail_body = get_encode_body(m, part.body)
            else
              # multipart/alternative�ł��t�@�C���ł�text/plain�ł��Ȃ��ꍇ�͉������Ȃ��i���肦�Ȃ��H�j
            end
          end # m.parts.each do
        else
          puts">>>>>>>>>>>>>>>>>>>>>>>>>>> SINGLEPART MODE"
          puts">>>>>>>>>>>>>>>>>>>>>>>>>>> REGIST MAIL BODY"
          # �p�[�g�ɕ�����Ă��Ȃ���΁Abody�����̂܂܃G���R�[�h���đ������
          import_mail.mail_body = get_encode_body(m, m.body)
        end # m.multipart?
        #---------- mail_body �����܂� ----------
        
        
        import_mail.created_user = 'import_mail'
        import_mail.updated_user = 'import_mail'
        import_mail.save!
        
        
      end # transaction
      puts">>>>>>>>>>>>>>>>>>>>>>>>>>> MAIL IMPORT END"
    end # Pop3Client.pop_mail do
  end # def

  def wanted?
    self.unwanted != 1
  end

  def set_bp
    mail_from = self.mail_from
    mail_bp_pic = BpPic.find(:first, :conditions => ["deleted = 0 and email1 = ? or email2 = ?", mail_from, mail_from])
    if mail_bp_pic.blank?
      mail_business_partner = BusinessPartner.find(:first, :conditions => ["deleted = 0 and email = ?", mail_from])
      if !mail_business_partner.blank?
        self.business_partner_id = mail_business_partner.id
      end
    else
      self.bp_pic_id = mail_bp_pic.id
      self.business_partner_id = mail_bp_pic.business_partner.id
    end
  end

  def get_bizp(id)
    return BusinessPartner.find(id)
  end

  def get_bpic(id)
    return BpPic.find(id)
  end

  def attachment?
    AttachmentFile.count(:conditions => ["deleted = 0 and parent_table_name = 'import_mails' and parent_id = ?", self]) > 0
#    !AttachmentFile.find(:first, :conditions => ["deleted = 0 and parent_table_name = 'import_mails' and parent_id = ?", self]).blank?
  end
  
  def change_type(type_name)
    if type_name == "biz_offer"
      self.biz_offer_flg = 1
      self.save!
    end
  end

private
  def ImportMail.get_encode_body(mail, body)
    if mail.transfer_encoding == 'ISO-2022-JP'
      return NKF.nkf('-w -J', body)
    elsif mail.transfer_encoding == 'UTF-8'
      return body
    else
      # ���̂ق���
      return NKF.nkf('-w', body)
    end
  end

CTYPE_TO_EXT = {
  'image/jpeg' => 'jpeg',
  'image/gif'  => 'gif',
  'image/png'  => 'png',
  'image/tiff' => 'tiff',
  'application/vnd.ms-excel' => 'xls',
  'application/msword' => 'doc'
}

def ext( mail )
  CTYPE_TO_EXT[mail.content_type] || 'txt'
end



end