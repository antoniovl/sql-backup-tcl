#!/usr/bin/tclsh
#
# Respalda una lista de bases de datos
# (c) UnixLibre
#

set config_file "sql-backup.conf"
set argvLen [llength $argv]

if {$argvLen == 1} {
	set config_file [lindex $argv 0]
} elseif {$argvLen == 0} {
	set config_file "sql-backup.conf"
} else {
	puts "sql-backup.tcl - (c) UnixLibre - http://www.unixlibre.org
	puts "Uso: $argv0 \[archivo.conf\]"
	exit 1
}

source $config_file


if {[info exists dbservers] == 0} {
	puts stderr "Debe establecer la variable dbservers en la configuracion."
	exit 1
}

if {[info exists quiet] == 0} {
	# Por default muestra mensajes.
	set quiet 0
}

if {[info exists compress_data] == 0} {
	# por default comprime
	set compress_data 1
}

if {[info exists data_dir] == 0} {
	set data_dir "."
}

if {[info exists dia_mes] == 0} {
	set dia_mes 1
}

if {[info exists dia_semana] == 0} {
	set dia_semana 7
}

if {[info exists logEmail] == 0} {
	set logEmail ""
}

if {[info exists logMode] == 0} {
	set LogMode 1
}

if {[info exists smtpHost] == 0} {
	set smtpHost localhost
}

if {[info exists timestamps] == 0} {
	set timestamps 0
}

set logFileHandler ""
set logFileOpen 0
set logBag ""
set dias [list lunes martes miercoles jueves viernes sabado domingo]

proc getDate {} {
	set d [clock seconds]
	set f [clock format $d -format "%Y-%m-%d %H:%M:%S"]
	return $f
}

# Obtiene el dia del mes
proc getToday {} {
	set d [clock seconds]
	set f [clock format $d -format "%d"]
	return $f
}

# Obtiene el dia de la semana, lunes=1, domingo=7
proc getWeekday {} {
	set d [clock seconds]
	set f [clock format $d -format "%u"]
	return $f
}

proc getWeekdayName {d} {
	global dias
	if {$d < 0} {
		return "Dia negativo ($d)?"
	}
	return [lindex $dias [expr $d - 1]]
}

proc getTimestampName {} {
	set d [clock seconds]
	return [clock format $d -format "%Y%m%d-%H%M"]
}

proc log {txt} {
	global logfile logFileHandler logFileOpen logMode logBag
	if {$logFileOpen == 0} {
		set mode "w"
		if {$logMode == 1} {
			set mode "w"
		} else {
			set mode "a"
		}
		set logFileHandler [open $logfile $mode]
		set logFileOpen 1
	}
	set t "[getDate]: $txt"
	set logBag "$logBag\n$txt"
	puts $logFileHandler $t
	flush $logFileHandler
}


proc print {m} {
	global logQuiet
	if {$logQuiet == 1} {
		return
	}
	puts $m
	flush stdout
}

proc print_nonewline {m} {
	global logQuiet
	if {$logQuiet == 1} {
		return
	}
	puts -nonewline $m
	flush stdout
}


proc mysql_bak {user pass host port db bakname} {
        global mysqldump data_dir env
        
        set opts {--opt -u $user -h $host --port=$port --single-transaction }
	set env(MYSQL_PWD) $pass
        
        catch { 
                eval exec $mysqldump $opts $db > $data_dir/$bakname 
        } err
        return $err
}

proc pgsql_bak {user pass host port db bakname} {
        global pgdump data_dir env
        
        set opts {-i -Fc -h $host -p $port -U $user -W $db}
        
        catch {
                set env(PGPASSWORD) $pass
                #set op "|$pgdump -i -Fp -b -h $host -p $port -U $user $db"
		set op "|$pgdump -h $host -p $port -U $user -Fp -b -O -E UTF8 -x $db"
                set op "$op > $data_dir/$bakname "
                set p [open $op w]
                puts $p $pass
                flush $p
        
                close $p
                set env(PGPASSWORD) ""
        } err
        return $err
}

# Variables de trabajo para el loop foreach
set nDb 0
set totalErroresDump 0
set totalErroresZip 0
print "sql-backup - unixmaster@unixlibre.org"
log "*** sql-backup - unixmaster@unixlibre.org ***" 

foreach dbserver $dbservers {
	
	flush stdout

	set nDb [expr $nDb + 1]
	set dbserv ""
	set dbPort ""
	set dbusr ""
	set dbpwd ""
	set db ""
	set dbn ""
	set dbtipo ""
	set dbFreq 0
	set dbZip 0
	set dbZipTest 0
	set msg "Procesando"

	if {[llength $dbserver] != 6} {
		log "El elemento dbserver $nDb está mal estructrado."
		continue
	} else {
	        # Servidor 
	        set dbserv [lindex $dbserver 0]
		# Puerto
		set dbPort [lindex $dbserver 1]
		# usuario
		set dbusr  [lindex $dbserver 2]
		# Password
		set dbpwd  [lindex $dbserver 3]
                # Tipo
                set dbtipo [lindex $dbserver 4]
	}

        # Itera para cada base de datos en la lista de DB
        foreach dbname [lindex $dbserver 5] {        

                set msg "Procesando"
                
                # Determina que tenga los elementos requeridos.
                if {[llength $dbname] != 4} {
                        log "El elemento dbname $dbname está mal estructrado."
                        continue
                }
                
                set db [lindex $dbname 0]
                
		if {$timestamps != 0} {
			set dbn "$db-[getTimestampName]"
		} else {
			set dbn "$db"
		}
		
		if {$dbtipo == "mysql"} {
		        set dbn "mysql-$dbn.sql"
		} else {
		        set dbn "pgsql-$dbn.backup"
		}
		
		set dbFreq [lindex $dbname 1]
		set dbZip [lindex $dbname 2]
		set dbZipTest [lindex $dbname 3]
		set msg "$msg $db@$dbserv ($dbtipo)"
		set msgFreq ""
		
        	# Determina si debe ejecutar el respaldo
        	if {$dbFreq == "mensual"} {
        		# mensual = 3
        		if {[getToday] != $dia_mes} {
        		        set errm "Ignorando a \"$db\" porque es"
        		        set errm "$errm mensual y hoy no es dia"
        		        set errm "$errm $dia_mes..."
        			print $errm
			        continue
        		}
        		set msgFreq "(mensual)"
        	} elseif {$dbFreq == "semanal"} {
        		# semanal = 2
        		if {[getWeekday] != $dia_semana} {
        		        set errm "Ignorando a \"$db\" porque es"
        		        set errm "$errm semanal y hoy no es"
        		        set errm "$errm [getWeekdayName $dia_semana]..." 
        			print $errm
        			continue
        		}
        		set msgFreq "(semanal)"
        	} else {
        	        # diario = 1
        		set msgFreq "(diario)"
        	}
	
        	# Las diarias se ejecutan todas
        	print_nonewline "$msg $msgFreq"
        	#catch { 
        	#	eval exec $mdump $opts $db > $data_dir/$dbn 
        	#} err
        	if {$dbtipo == "mysql"} {
        	        set err [mysql_bak $dbusr $dbpwd $dbserv $dbPort $db $dbn]
        	} else {
        	        set err [pgsql_bak $dbusr $dbpwd $dbserv $dbPort $db $dbn]
        	}
	
        	if {[string compare $err ""] != 0} {
        		print "Error: $err"
        		log "Error al ejecutar backup: $err"
        		set totalErroresDump [expr $totalErroresDump + 1]
        		# Si hubo problemas en teoria no hay nada que comprimir
        		continue
        	} else {
        		print_nonewline "(dump Ok) "
        		log "$db $msgFreq -> Ok"
        	}
	
        	set err ""
        	
        	if {$dbZip == "si"} {
        		#print_nonewline "Comprimiendo $dbn..."
        		flush stdout
        		catch {
        			eval exec $bzip2 -f -9 $data_dir/$dbn
        		} err
        		if {[string compare $err ""] != 0} {
        			print "Error: $err"
        			log "Error al ejecutar $bzip2: $err"
        			set totalErroresZip [expr $totalErroresZip + 1]
        		} else {
        			print_nonewline "(bzip2 ok) "
        			log "$bzip2 $db -> Ok"
        		}
        		
        	        # Si es necesario verificar, verifica integridad.
		        if {$dbZipTest == "si"} {
		        	set err ""
		        	catch {
		        		eval exec $bzip2 -t "$data_dir/$dbn.bz2"
		        	} err
		        	if {[string compare $err ""] != 0} {
		        		print "Error de Integridad en bz2: $err"
		        		log "Error de Integridad en bz2: $err"
			        	set totalErroresZip [expr $totalErroresZip + 1]
		        	} else {
		        		print_nonewline "(bzip2 test Ok)"
		        		log "$bzip2 test $db -> Ok"
		        	}
		        }
	        }
	
	        print ""
	        flush stdout
	}
}


log "Total de Errores en backup: $totalErroresDump"
log "Total de Errores en $bzip2: $totalErroresZip"



