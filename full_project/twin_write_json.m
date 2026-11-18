function twin_write_json(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true));
end
