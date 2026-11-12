function njulogin --description 'Log in to the Nanjing University network portal'
    command curl --data "{\"username\":\"$NJU_LOGIN_USERNAME\",\"password\":\"$NJU_LOGIN_PASSWORD\",\"domain\":\"default\"}" https://p.nju.edu.cn/api/portal/v1/login
end
