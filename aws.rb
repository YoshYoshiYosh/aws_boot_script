require 'aws-sdk'

Aws.config.update({
  credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
})

puts "AWSインスタンスを起動しますか？停止しますか？\n[1]起動する [2]停止する"

operation = 
  case gets.to_i
  when 1
    print "リージョンを入力してください："
    user_region = gets.chomp
    
    print "EC2インスタンスのIDを入力してください："
    ec2_instance_id = gets.chomp
    
    print "RDSインスタンスの名称を入力してください："
    rds_instance_name = gets.chomp

    'boot'
  when 2
    'stop'
  else
    '?'
  end
  
define_method :setup do
  # EC2インスタンスを作成する
  client = Aws::EC2::Client.new(region: user_region)
  ec2 = Aws::EC2::Resource.new(client: client)
  ec2_instance = ec2.instance(ec2_instance_id)

  # RDSインスタンスを作成する
  rds_client = Aws::RDS::Client.new(region: user_region)
  rds = Aws::RDS::Resource.new(client: rds_client)
  rds_instance = rds.db_instance(rds_instance_name)
end

define_method :public_ip_not_allocated? do
  if ec2_instance.network_interfaces.first.data.association.ip_owner_id == 'amazon'
    true
  else
    false
  end
end

define_method :ec2_booted? do
  ec2_instance.state.code == 16 ? true : false
end

define_method :elip_allocated? do
  ec2_instance.network_interfaces.first.data.association.ip_owner_id != 'amazon' ? true : false
end

define_method :rds_booted? do
  rds_instance.data.db_instance_status == 'available' ? true : false
end

define_method :boot_aws do
  until ec2_booted? && elip_allocated? && rds_booted?
    # EC2インスタンス起動
    if ec2_instance.exists? && !ec2_booted?
      case ec2_instance.state.code
      when 80
        puts "#{ec2_instance.id} is stopped, booting now..."
        ec2_instance.start
      when 16
        puts "#{ec2_instance.id} is already running."
      end
    end
  
    # Elastic IP割り当て
    if ec2_instance.state.code == 16 && public_ip_not_allocated?
      resp = client.allocate_address
      client.associate_address(instance_id: ec2_instance.id, allocation_id: resp.allocation_id)
      puts "#{resp.allocation_id} is allocated to #{ec2_instance.id}."
    end
  
    # RDS起動
    if rds_instance.data.db_instance_status == 'stopped'
      puts "#{rds_instance.data.db_instance_identifier} is stopped, booting now..."
      rds_client.start_db_instance({ db_instance_identifier: 'aws-and-infra-web' })
    end
  
    ec2_instance.reload
    rds_instance.reload
    sleep(15)
  end
end

if operation == 'boot'
  setup
  boot_aws
  puts '起動完了しました。'
elsif operation == 'stop'
  puts "（未対応）停止させるコードを書く。"
end